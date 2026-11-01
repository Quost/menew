import AppKit
import SwiftUI

struct Accessory: Identifiable, Equatable {
    var id: String { name + kind }
    let name: String
    /// "mouse", "keyboard", "trackpad", "headphones", "other"
    let kind: String
    /// Partes com bateria: só "main", ou "left", "right" e "case" (AirPods)
    let levels: [(part: String, percent: Int)]

    static func == (a: Accessory, b: Accessory) -> Bool {
        a.name == b.name && a.levels.map(\.percent) == b.levels.map(\.percent)
    }

    var lowest: Int { levels.map(\.percent).min() ?? 100 }

    var icon: String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        switch kind {
        case "mouse": return "magicmouse.fill"
        case "keyboard": return "keyboard.fill"
        case "trackpad": return "rectangle.and.hand.point.up.left.fill"
        case "headphones": return "headphones"
        default: return "battery.75percent"
        }
    }
}

/// Bateria de mouse, teclado, trackpad e AirPods conectados. Lido do macOS (system_profiler e IORegistry),
/// só quando a aba Sistema está aberta e a cada 10 minutos para o aviso de bateria baixa.
@MainActor
final class AccessoryMonitor: ObservableObject {
    static let shared = AccessoryMonitor()
    static let alertKey = "alertAccessories"
    @Published private(set) var devices: [Accessory] = []
    private var timer: Timer?
    private var warned: [String: Date] = [:]
    private var loading = false
    private var demo = false

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            MainActor.assumeIsolated { AccessoryMonitor.shared.refresh() }
        }
        timer?.tolerance = 60
    }

    func refresh() {
        guard !loading, !demo else { return }
        loading = true
        Task {
            let found = await Task.detached { Self.read() }.value
            loading = false
            if found != devices { devices = found }
            warnLow()
        }
    }

    /// Um aviso por acessório a cada 12 horas, abaixo de 15%
    private func warnLow() {
        guard UserDefaults.standard.bool(forKey: Self.alertKey) else { return }
        for d in devices where d.lowest <= 15 {
            if let last = warned[d.name], Date().timeIntervalSince(last) < 12 * 3600 { continue }
            warned[d.name] = Date()
            Alerts.shared.notify(id: "accessory.\(d.name)", title: L("Bateria baixa: %@", d.name),
                                 body: L("%d%% restantes. Hora de carregar.", d.lowest))
        }
    }

    nonisolated private static func read() -> [Accessory] {
        var out = parseProfiler(Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]))
        // Teclados e trackpads de cabo ou que o system_profiler não mostra: IORegistry
        for d in parseIORegistry(Shell.run("/usr/sbin/ioreg", ["-r", "-k", "BatteryPercent", "-l"]))
        where !out.contains(where: { $0.name == d.name }) {
            out.append(d)
        }
        return out.sorted { $0.name < $1.name }
    }

    /// JSON do `system_profiler SPBluetoothDataType -json`
    nonisolated static func parseProfiler(_ json: String) -> [Accessory] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = bt["device_connected"] as? [[String: Any]] else { return [] }
        var out: [Accessory] = []
        for entry in connected {
            for (name, value) in entry {
                guard let info = value as? [String: Any] else { continue }
                var levels: [(String, Int)] = []
                for (key, part) in [("device_batteryLevelMain", "main"), ("device_batteryLevelLeft", "left"),
                                    ("device_batteryLevelRight", "right"), ("device_batteryLevelCase", "case")] {
                    if let s = info[key] as? String, let n = Int(s.filter(\.isNumber)) { levels.append((part, n)) }
                }
                guard !levels.isEmpty else { continue }
                let minor = (info["device_minorType"] as? String ?? "").lowercased()
                let kind = minor.contains("mouse") ? "mouse" : minor.contains("keyboard") ? "keyboard"
                    : minor.contains("trackpad") ? "trackpad" : (minor.contains("headphone") || minor.contains("headset")) ? "headphones" : "other"
                out.append(Accessory(name: name, kind: kind, levels: levels))
            }
        }
        return out
    }

    /// Saída do `ioreg -r -k BatteryPercent -l`: "Product" e "BatteryPercent" de cada dispositivo
    nonisolated static func parseIORegistry(_ text: String) -> [Accessory] {
        var out: [Accessory] = []
        var product: String?, percent: Int?
        func flush() {
            if let product, let percent, (0...100).contains(percent) {
                let n = product.lowercased()
                let kind = n.contains("mouse") ? "mouse" : n.contains("keyboard") ? "keyboard" : n.contains("trackpad") ? "trackpad" : "other"
                out.append(Accessory(name: product, kind: kind, levels: [("main", percent)]))
            }
            product = nil; percent = nil
        }
        for line in text.split(separator: "\n") {
            if line.contains("+-o ") { flush() }
            if let r = line.range(of: "\"Product\" = \"") {
                product = String(line[r.upperBound...].prefix { $0 != "\"" })
            } else if let r = line.range(of: "\"BatteryPercent\" = ") {
                percent = Int(line[r.upperBound...].prefix { $0.isNumber })
            }
        }
        flush()
        return out
    }

    /// Para as capturas de tela
    func showDemo() {
        demo = true
        devices = [
            Accessory(name: "AirPods Pro", kind: "headphones", levels: [("left", 80), ("right", 75), ("case", 40)]),
            Accessory(name: "Magic Keyboard", kind: "keyboard", levels: [("main", 92)]),
            Accessory(name: "Magic Mouse", kind: "mouse", levels: [("main", 12)]),
        ]
    }
}

/// Cartão "Acessórios" na aba Sistema (só aparece com algum acessório com bateria)
struct AccessoriesCard: View {
    @ObservedObject var monitor = AccessoryMonitor.shared

    var body: some View {
        if !monitor.devices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: L("Acessórios"), icon: "battery.75percent", color: .green)
                ForEach(monitor.devices) { d in
                    HStack(spacing: 10) {
                        Image(systemName: d.icon).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 22)
                        Text(d.name).font(.system(size: 12.5)).lineLimit(1)
                        Spacer(minLength: 6)
                        ForEach(d.levels, id: \.part) { level in
                            HStack(spacing: 3) {
                                if d.levels.count > 1 {
                                    Text(partLabel(level.part)).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                                }
                                Text("\(level.percent)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(level.percent <= 15 ? Color.red : level.percent <= 30 ? .orange : .primary)
                            }
                        }
                    }
                }
            }
            .card(padding: 14)
        }
    }

    private func partLabel(_ p: String) -> String {
        switch p {
        case "left": L("E")
        case "right": L("D")
        case "case": L("Estojo")
        default: ""
        }
    }
}
