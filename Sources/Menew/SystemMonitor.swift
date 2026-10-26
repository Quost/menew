import Foundation
import Darwin
import IOKit.ps

struct BatteryInfo {
    var percent: Int
    var charging: Bool
    var onAC: Bool
    var minutesLeft: Int?
}

struct ProcInfo: Identifiable {
    let id = UUID()
    let name: String
    let cpu: Double
    let memKB: UInt64
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published var cpu: Double = 0
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var memUsed: UInt64 = 0
    @Published var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var battery: BatteryInfo?
    @Published var netIn: Double = 0
    @Published var netOut: Double = 0
    @Published var netInHistory: [Double] = Array(repeating: 0, count: 40)
    @Published var netOutHistory: [Double] = Array(repeating: 0, count: 40)
    @Published var localIP: String = "—"
    @Published var uptime: TimeInterval = 0
    @Published var thermal: ProcessInfo.ThermalState = .nominal
    @Published var topProcesses: [ProcInfo] = []

    var wantsProcesses = false
    /// Modo captura de tela: não sobrescreve IP e processos fictícios
    var isDemo = false
    var onTick: (() -> Void)?

    private var timer: Timer?
    private var prevTicks: (user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64)?
    private var prevNet: (rx: UInt64, tx: UInt64, at: Date)?
    private var tickCount = 0

    let cores = ProcessInfo.processInfo.activeProcessorCount
    var memFraction: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) }
    var diskFraction: Double { diskTotal == 0 ? 0 : 1 - Double(diskFree) / Double(diskTotal) }

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        tickCount += 1
        readCPU()
        readMemory()
        readNetwork()
        uptime = ProcessInfo.processInfo.systemUptime
        thermal = ProcessInfo.processInfo.thermalState
        // Itens que mudam devagar: a cada ~10s
        if tickCount % 5 == 1 {
            readDisk()
            battery = Self.readBattery()
            if !isDemo { localIP = Self.readLocalIP() ?? "—" }
        }
        if wantsProcesses { refreshProcesses() }
        onTick?()
    }

    // MARK: CPU

    private func readCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let t = (user: UInt64(info.cpu_ticks.0), sys: UInt64(info.cpu_ticks.1),
                 idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
        if let p = prevTicks {
            let busy = Double((t.user &- p.user) + (t.sys &- p.sys) + (t.nice &- p.nice))
            let total = busy + Double(t.idle &- p.idle)
            cpu = total > 0 ? min(max(busy / total, 0), 1) : 0
            cpuHistory.removeFirst()
            cpuHistory.append(cpu)
        }
        prevTicks = t
    }

    // MARK: Memória (mesma conta do Monitor de Atividade: app + wired + comprimida)

    private func readMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)
        let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        memUsed = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    // MARK: Disco

    private func readDisk() {
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        }
    }

    // MARK: Rede

    private func readNetwork() {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            let name = String(cString: ifa.ifa_name)
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               !name.hasPrefix("lo"), let data = ifa.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(d.ifi_ibytes)
                tx += UInt64(d.ifi_obytes)
            }
            ptr = ifa.ifa_next
        }
        let now = Date()
        if let p = prevNet {
            let dt = now.timeIntervalSince(p.at)
            if dt > 0 {
                netIn = rx >= p.rx ? Double(rx - p.rx) / dt : 0
                netOut = tx >= p.tx ? Double(tx - p.tx) / dt : 0
                netInHistory.removeFirst(); netInHistory.append(netIn)
                netOutHistory.removeFirst(); netOutHistory.append(netOut)
            }
        }
        prevNet = (rx, tx, now)
    }

    private static func readLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            let name = String(cString: ifa.ifa_name)
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), name.hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            ptr = ifa.ifa_next
        }
        return nil
    }

    // MARK: Bateria

    private static func readBattery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let mx = max(d[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let tte = d[kIOPSTimeToEmptyKey] as? Int ?? -1
            let ttf = d[kIOPSTimeToFullChargeKey] as? Int ?? -1
            let minutes = charging ? ttf : (onAC ? -1 : tte)
            return BatteryInfo(percent: cur * 100 / mx, charging: charging, onAC: onAC,
                               minutesLeft: minutes > 0 ? minutes : nil)
        }
        return nil
    }

    // MARK: Processos

    func refreshProcesses() {
        guard !isDemo else { return }
        Task {
            let list = await Task.detached { Self.readTopProcesses() }.value
            self.topProcesses = list
        }
    }

    nonisolated private static func readTopProcesses() -> [ProcInfo] {
        let out = Shell.run("/bin/ps", ["-Aceo", "pcpu=,rss=,comm=", "-r"])
        return out.split(separator: "\n").prefix(6).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let cpu = Double(parts[0]) else { return nil }
            return ProcInfo(name: String(parts[2]), cpu: cpu, memKB: UInt64(parts[1]) ?? 0)
        }
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
    static func mem(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory)
    }
    /// "12,3 GB" / "16 GB"
    static func memShort(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        return (gb >= 10 || gb.rounded() == gb ? String(format: "%.0f", gb) : String(format: "%.1f", locale: L10n.locale, gb)) + " GB"
    }
    static func rate(_ bps: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
    }
    /// Versão curta para a barra de menus: 1.2M, 340K
    static func shortRate(_ bps: Double) -> String {
        switch bps {
        case ..<1_000: return String(format: "%.0fB", bps)
        case ..<1_000_000: return String(format: "%.0fK", bps / 1_000)
        default: return String(format: "%.1fM", bps / 1_000_000)
        }
    }
    static func pct(_ f: Double) -> String { String(format: "%.0f%%", f * 100) }
    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t)
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60
        return d > 0 ? "\(d)d \(h)h \(m)min" : "\(h)h \(m)min"
    }
}
