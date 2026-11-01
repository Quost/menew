import Foundation
import IOKit
import SwiftUI

/// Temperaturas e ventoinhas, só leitura. Os sensores de temperatura vêm do sistema de eventos HID do macOS e as
/// ventoinhas do SMC, como o app Stats faz. São interfaces internas da Apple: se uma atualização do macOS mudar algo,
/// o Menew só deixa de mostrar aquele número (nada trava, nada é alterado no Mac).
@MainActor
final class Sensors: ObservableObject {
    static let shared = Sensors()

    struct Fan: Equatable { let rpm: Double; let min: Double; let max: Double }

    @Published private(set) var chip: Double?
    @Published private(set) var chipAverage: Double?
    @Published private(set) var ssd: Double?
    @Published private(set) var battery: Double?
    @Published private(set) var fans: [Fan] = []
    /// Todos os sensores, para a lista completa
    @Published private(set) var all: [(name: String, celsius: Double)] = []

    private var last = Date.distantPast
    private var demo = false

    var hasData: Bool { chip != nil || !fans.isEmpty }

    /// No máximo uma leitura a cada 2 s
    func refresh() {
        guard !demo, Date().timeIntervalSince(last) >= 2 else { return }
        last = Date()
        Task {
            let (temps, fanList) = await Task.detached(priority: .utility) { (HIDTemperatures.read(), SMC.fans()) }.value
            apply(temps, fanList)
        }
    }

    private func apply(_ temps: [(String, Double)], _ fanList: [Fan]) {
        let valid = temps.filter { $0.1 > 5 && $0.1 < 130 }
        let die = valid.filter { $0.0.contains("tdie") }.map(\.1)
        chip = die.max()
        chipAverage = die.isEmpty ? nil : die.reduce(0, +) / Double(die.count)
        ssd = valid.filter { $0.0.hasPrefix("NAND") }.map(\.1).max()
        let bat = valid.filter { $0.0.contains("battery") }.map(\.1)
        battery = bat.isEmpty ? nil : bat.reduce(0, +) / Double(bat.count)
        fans = fanList
        // Nomes repetidos (vários sensores de bateria) viram um só, com a média
        var grouped: [String: [Double]] = [:]
        for (n, v) in valid { grouped[n, default: []].append(v) }
        all = grouped.map { ($0.key, $0.value.reduce(0, +) / Double($0.value.count)) }.sorted { $0.name < $1.name }
    }

    func showDemo() {
        demo = true
        chip = 52; chipAverage = 46; ssd = 38; battery = 31
        fans = [Fan(rpm: 2500, min: 2300, max: 6550)]
        all = [("NAND CH0 temp", 38), ("PMU tdie1", 47), ("PMU tdie8", 52), ("gas gauge battery", 31)]
    }

    static func color(_ c: Double) -> Color { c >= 90 ? .red : c >= 75 ? .orange : c >= 60 ? .yellow : .green }
}

// MARK: Temperaturas (HID)

private enum HIDTemperatures {
    typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Int32
    typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    typealias CopyPropFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    /// As funções são procuradas na hora: se sumirem num macOS futuro, simplesmente não há temperaturas
    private struct Fns {
        let create: CreateFn, setMatching: SetMatchingFn, copyServices: CopyServicesFn
        let copyProp: CopyPropFn, copyEvent: CopyEventFn, getFloat: GetFloatFn
    }

    nonisolated(unsafe) private static let fns: Fns? = {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let a = dlsym(h, "IOHIDEventSystemClientCreate"), let b = dlsym(h, "IOHIDEventSystemClientSetMatching"),
              let c = dlsym(h, "IOHIDEventSystemClientCopyServices"), let d = dlsym(h, "IOHIDServiceClientCopyProperty"),
              let e = dlsym(h, "IOHIDServiceClientCopyEvent"), let f = dlsym(h, "IOHIDEventGetFloatValue") else { return nil }
        return Fns(create: unsafeBitCast(a, to: CreateFn.self), setMatching: unsafeBitCast(b, to: SetMatchingFn.self),
                   copyServices: unsafeBitCast(c, to: CopyServicesFn.self), copyProp: unsafeBitCast(d, to: CopyPropFn.self),
                   copyEvent: unsafeBitCast(e, to: CopyEventFn.self), getFloat: unsafeBitCast(f, to: GetFloatFn.self))
    }()

    nonisolated(unsafe) private static var client: AnyObject?

    static func read() -> [(String, Double)] {
        guard let f = fns else { return [] }
        if client == nil, let c = f.create(kCFAllocatorDefault)?.takeRetainedValue() {
            _ = f.setMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
            client = c
        }
        guard let client, let services = f.copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return [] }
        var out: [(String, Double)] = []
        for s in services {
            guard let name = f.copyProp(s, "Product" as CFString)?.takeRetainedValue() as? String,
                  let ev = f.copyEvent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
            out.append((name, f.getFloat(ev, 15 << 16)))
        }
        return out
    }
}

// MARK: Ventoinhas (SMC)

private enum SMC {
    struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }
    /// Mesmo formato (80 bytes) da estrutura que o AppleSMC espera
    struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    nonisolated(unsafe) private static var conn: io_connect_t = 0

    private static func open() -> Bool {
        if conn != 0 { return true }
        guard MemoryLayout<Param>.size == 80 else { return false }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return false }
        defer { IOObjectRelease(svc) }
        return IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS
    }

    private static func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.size
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<Param>.size, &output, &size)
        return r == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private static func value(_ key: String) -> Double? {
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        var info = Param(); info.key = code; info.data8 = 9
        guard let i = call(&info) else { return nil }
        var req = Param(); req.key = code; req.keyInfo.dataSize = i.keyInfo.dataSize; req.data8 = 5
        guard let out = call(&req) else { return nil }
        let b = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(i.keyInfo.dataSize))) }
        switch i.keyInfo.dataType {
        case 0x666C_7420 where b.count >= 4: return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })  // "flt "
        case 0x6670_6532 where b.count >= 2: return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4                    // "fpe2"
        case 0x7569_3820 where b.count >= 1: return Double(b[0])                                                    // "ui8 "
        default: return nil
        }
    }

    static func fans() -> [Sensors.Fan] {
        guard open(), let n = value("FNum"), n > 0 else { return [] }
        return (0..<min(Int(n), 4)).compactMap { i in
            guard let rpm = value("F\(i)Ac") else { return nil }
            return Sensors.Fan(rpm: rpm, min: value("F\(i)Mn") ?? 0, max: value("F\(i)Mx") ?? 0)
        }
    }
}

// MARK: Tela

/// Cartão "Temperaturas" na aba Sistema
struct SensorsCard: View {
    @ObservedObject var sensors = Sensors.shared
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: L("Temperaturas"), icon: "thermometer.medium", color: .orange)
            if let c = sensors.chip { row(L("Chip"), c, detail: sensors.chipAverage.map { L("média %d °C", Int($0)) }) }
            if let s = sensors.ssd { row("SSD", s, detail: nil) }
            if let b = sensors.battery { row(L("Bateria"), b, detail: nil) }
            ForEach(Array(sensors.fans.enumerated()), id: \.offset) { i, f in
                HStack(spacing: 8) {
                    Image(systemName: "fan.fill").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
                    Text(sensors.fans.count > 1 ? L("Ventoinha %d", i + 1) : L("Ventoinha")).font(.system(size: 12))
                    Spacer(minLength: 6)
                    bar(f.max > 0 ? (f.rpm - f.min) / max(1, f.max - f.min) : 0, .blue)
                    Text(L("%d rpm", Int(f.rpm))).font(.system(size: 12, weight: .semibold)).monospacedDigit().frame(width: 74, alignment: .trailing)
                }
            }
            if !sensors.all.isEmpty {
                Button { withAnimation(.snappy) { showAll.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(showAll ? L("Esconder os %d sensores", sensors.all.count) : L("Ver os %d sensores", sensors.all.count))
                        Image(systemName: "chevron.down").rotationEffect(.degrees(showAll ? 180 : 0))
                    }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if showAll {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                        ForEach(sensors.all, id: \.name) { s in
                            HStack {
                                Text(s.name).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 2)
                                Text(String(format: "%.0f°", s.celsius)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .card()
        .onAppear { sensors.refresh() }
    }

    private func row(_ title: String, _ c: Double, detail: String?) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Sensors.color(c)).frame(width: 7, height: 7).frame(width: 16)
            Text(title).font(.system(size: 12))
            if let detail { Text(detail).font(.system(size: 10.5)).foregroundStyle(.tertiary) }
            Spacer(minLength: 6)
            bar(min(1, max(0, (c - 25) / 80)), Sensors.color(c))
            Text(String(format: "%.0f °C", c)).font(.system(size: 12, weight: .semibold)).monospacedDigit().frame(width: 74, alignment: .trailing)
        }
    }

    private func bar(_ v: Double, _ color: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.08))
            Capsule().fill(color.opacity(0.8)).frame(width: max(4, 70 * v))
        }
        .frame(width: 70, height: 5)
    }
}
