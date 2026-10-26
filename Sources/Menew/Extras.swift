import Foundation
import IOKit

// MARK: Dispositivos Bluetooth

struct BTDevice: Identifiable {
    enum Kind { case airpods, headphones, mouse, keyboard, trackpad, other }
    var id: String { name }
    let name: String
    let kind: Kind
    let levels: [(label: String, percent: Int)]

    var icon: String {
        switch kind {
        case .airpods: "airpodspro"
        case .headphones: "headphones"
        case .mouse: "magicmouse.fill"
        case .keyboard: "keyboard.fill"
        case .trackpad: "rectangle.and.hand.point.up.left.fill"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

enum Bluetooth {
    static func devices() -> [BTDevice] {
        var result = fromSystemProfiler()
        for d in fromHID() where !result.contains(where: { $0.name == d.name }) { result.append(d) }
        return result
    }

    /// AirPods, fones e afins: o system_profiler expõe esquerdo/direito/estojo
    private static func fromSystemProfiler() -> [BTDevice] {
        let out = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
        guard let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              let root = (json["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = root["device_connected"] as? [[String: Any]] else { return [] }
        var list: [BTDevice] = []
        for entry in connected {
            for (name, value) in entry {
                guard let info = value as? [String: Any] else { continue }
                let pct: (String) -> Int? = { key in
                    (info[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
                }
                var levels: [(String, Int)] = []
                if let v = pct("device_batteryLevelLeft") { levels.append(("E", v)) }
                if let v = pct("device_batteryLevelRight") { levels.append(("D", v)) }
                if let v = pct("device_batteryLevelCase") { levels.append(("Estojo", v)) }
                if let v = pct("device_batteryLevelMain") { levels.append(("", v)) }
                guard !levels.isEmpty else { continue }
                let minor = (info["device_minorType"] as? String ?? "").lowercased()
                let lname = name.lowercased()
                let kind: BTDevice.Kind = lname.contains("airpods") ? .airpods
                    : minor.contains("headphone") || minor.contains("headset") ? .headphones
                    : minor.contains("mouse") ? .mouse
                    : minor.contains("keyboard") ? .keyboard
                    : minor.contains("trackpad") ? .trackpad : .other
                list.append(BTDevice(name: name, kind: kind, levels: levels))
            }
        }
        return list
    }

    /// Magic Mouse / Keyboard / Trackpad via IOKit
    private static func fromHID() -> [BTDevice] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        var list: [BTDevice] = []
        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }
            func prop(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let pct = prop("BatteryPercent") as? Int, let name = prop("Product") as? String,
                  !name.contains("Internal") else { continue }
            let l = name.lowercased()
            let kind: BTDevice.Kind = l.contains("mouse") ? .mouse : l.contains("keyboard") ? .keyboard
                : l.contains("trackpad") ? .trackpad : .other
            list.append(BTDevice(name: name, kind: kind, levels: [("", pct)]))
        }
        return list
    }
}

// MARK: Internet (IP público + teste de velocidade)

struct SpeedResult {
    let down: Double   // Mbps
    let up: Double
    let latency: Double // ms
    let rpm: Double    // responsividade (rodadas por minuto)

    var quality: String {
        switch rpm {
        case ..<200: "Responsividade baixa"
        case ..<800: "Responsividade média"
        default: "Responsividade alta"
        }
    }
}

@MainActor
final class InternetInfo: ObservableObject {
    enum SpeedState { case idle, running, done(SpeedResult), failed }

    @Published var publicIP: String?
    @Published var speed: SpeedState = .idle
    @Published var devices: [BTDevice] = []

    private var ipFetchedAt: Date?
    private var devicesFetchedAt: Date?

    func refreshIfNeeded() {
        if ipFetchedAt.map({ Date().timeIntervalSince($0) > 600 }) ?? true { fetchPublicIP() }
        if devicesFetchedAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true { refreshDevices() }
    }

    func fetchPublicIP() {
        ipFetchedAt = Date()
        Task {
            guard let url = URL(string: "https://api.ipify.org"),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { publicIP = nil; return }
            publicIP = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func refreshDevices() {
        devicesFetchedAt = Date()
        Task {
            devices = await Task.detached { Bluetooth.devices() }.value
        }
    }

    func runSpeedTest() {
        if case .running = speed { return }
        speed = .running
        Task {
            let out = await Task.detached { Shell.run("/usr/bin/networkQuality", ["-c"]) }.value
            guard let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
                  let dl = json["dl_throughput"] as? Double, let ul = json["ul_throughput"] as? Double else {
                speed = .failed
                return
            }
            speed = .done(SpeedResult(down: dl / 1_000_000, up: ul / 1_000_000,
                                      latency: json["base_rtt"] as? Double ?? 0,
                                      rpm: json["responsiveness"] as? Double ?? 0))
        }
    }
}

// MARK: Notas

@MainActor
final class NotesStore: ObservableObject {
    @Published var text: String = "" {
        didSet { scheduleSave() }
    }
    private let url: URL
    private var saveWork: DispatchWorkItem?

    init(dir: URL) {
        url = dir.appendingPathComponent("notas.md")
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = text, url = url
        let work = DispatchWorkItem { try? snapshot.write(to: url, atomically: true, encoding: .utf8) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
