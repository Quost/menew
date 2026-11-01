import SwiftUI

/// Regras de alerta que você monta, como no iStat Menus: "CPU acima de 80% por 10 min", "Bateria abaixo de 30%"…
/// Avisa uma vez quando a condição dura o tempo pedido e volta a avisar só depois de ela passar.
struct AlertRule: Codable, Identifiable, Equatable {
    enum Metric: String, Codable, CaseIterable, Identifiable {
        case cpu, memory, temp, battery, diskFree, netDown, netUp
        var id: String { rawValue }

        var title: String {
            switch self {
            case .cpu: "CPU"
            case .memory: L("Memória")
            case .temp: L("Temperatura do chip")
            case .battery: L("Bateria")
            case .diskFree: L("Espaço livre")
            case .netDown: L("Download")
            case .netUp: L("Upload")
            }
        }
        var unit: String {
            switch self {
            case .cpu, .memory, .battery: "%"
            case .temp: "°C"
            case .diskFree: "GB"
            case .netDown, .netUp: "MB/s"
            }
        }
        var icon: String {
            switch self {
            case .cpu: "cpu"
            case .memory: "memorychip"
            case .temp: "thermometer.medium"
            case .battery: "battery.50percent"
            case .diskFree: "internaldrive"
            case .netDown: "arrow.down"
            case .netUp: "arrow.up"
            }
        }
        /// Sugestão ao escolher a métrica
        var suggestion: (above: Bool, value: Double) {
            switch self {
            case .cpu: (true, 80)
            case .memory: (true, 90)
            case .temp: (true, 90)
            case .battery: (false, 30)
            case .diskFree: (false, 20)
            case .netDown, .netUp: (true, 5)
            }
        }
    }

    var id = UUID()
    var metric: Metric
    var above: Bool
    var threshold: Double
    var minutes: Int
    var enabled = true

    /// "CPU acima de 80% por 10 min"
    var summary: String {
        let v = threshold.rounded() == threshold ? "\(Int(threshold))" : String(format: "%.1f", threshold)
        let cond = above ? L("%@ acima de %@", metric.title, v + metric.unit) : L("%@ abaixo de %@", metric.title, v + metric.unit)
        return minutes > 0 ? cond + " " + L("por %d min", minutes) : cond
    }

    @MainActor func value(_ m: SystemMonitor) -> Double? {
        switch metric {
        case .cpu: m.cpu * 100
        case .memory: m.memFraction * 100
        case .temp: Sensors.shared.chip
        case .battery: m.battery.map { Double($0.percent) }
        case .diskFree: m.diskTotal > 0 ? Double(m.diskFree) / 1e9 : nil
        case .netDown: m.netIn / 1e6
        case .netUp: m.netOut / 1e6
        }
    }
}

@MainActor
final class AlertRules: ObservableObject {
    static let shared = AlertRules()
    static let key = "alertRules"

    @Published var rules: [AlertRule] {
        didSet { save() }
    }
    /// Desde quando cada regra está com a condição verdadeira, e quais já avisaram
    private var since: [UUID: Date] = [:]
    private var fired: Set<UUID> = []

    init() {
        rules = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([AlertRule].self, from: $0) } ?? []
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func check(_ m: SystemMonitor, now: Date = Date()) {
        let active = rules.filter(\.enabled)
        guard !active.isEmpty else { return }
        if active.contains(where: { $0.metric == .temp }) { Sensors.shared.refresh() }
        for r in active {
            guard let v = r.value(m) else { continue }
            let hit = r.above ? v > r.threshold : v < r.threshold
            guard hit else { since[r.id] = nil; fired.remove(r.id); continue }
            let start = since[r.id] ?? now
            since[r.id] = start
            if now.timeIntervalSince(start) >= Double(r.minutes * 60), !fired.contains(r.id) {
                fired.insert(r.id)
                Alerts.shared.notify(id: "rule-\(r.id)", title: L("Alerta do Menew"), body: r.summary)
            }
        }
    }

    /// Para os testes: quais regras avisariam agora
    func firedRules() -> [AlertRule] { rules.filter { fired.contains($0.id) } }
}

/// Lista de regras e o editor para criar uma nova, em Ajustes → Alertas
struct AlertRulesSection: View {
    @ObservedObject var store = AlertRules.shared
    @State private var metric: AlertRule.Metric = .cpu
    @State private var above = true
    @State private var threshold = 80.0
    @State private var minutes = 10

    var body: some View {
        GlassSection(title: L("Regras personalizadas"),
                     footer: L("Monte seus próprios alertas: escolha o que medir, o limite e por quanto tempo.")) {
            ForEach($store.rules) { $rule in
                SettingRow(title: rule.summary, icon: rule.metric.icon) {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        Button { store.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel(L("Apagar"))
                    }
                }
                RowDivider()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("", selection: $metric) {
                        ForEach(AlertRule.Metric.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    .onChange(of: metric) { _, m in above = m.suggestion.above; threshold = m.suggestion.value }
                    Picker("", selection: $above) {
                        Text(L("acima de")).tag(true)
                        Text(L("abaixo de")).tag(false)
                    }
                    .labelsHidden().fixedSize()
                    TextField("", value: $threshold, format: .number).textFieldStyle(.roundedBorder).frame(width: 56)
                    Text(metric.unit).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Stepper(minutes == 0 ? L("na hora") : L("por %d min", minutes), value: $minutes, in: 0...120, step: minutes < 5 ? 1 : 5)
                        .font(.system(size: 12))
                    Spacer()
                    PillButton(title: L("Adicionar regra"), icon: "plus", primary: true) {
                        store.rules.append(AlertRule(metric: metric, above: above, threshold: threshold, minutes: minutes))
                        Alerts.shared.requestPermission { _ in }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}
