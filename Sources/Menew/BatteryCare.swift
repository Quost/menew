import AppKit
import SwiftUI

/// Saúde da bateria ao longo do tempo: uma leitura por dia (saúde e ciclos) num arquivo pequeno no Mac,
/// para mostrar quanto ela caiu e quantos ciclos você usa por mês. Sem precisar de senha de administrador.
@MainActor
final class BatteryLog {
    static let shared = BatteryLog()

    struct Entry: Codable, Equatable {
        var day: String
        var health: Int
        var cycles: Int
    }

    private(set) var entries: [Entry] = []
    private var url: URL?

    func load(dir: URL) {
        url = dir.appendingPathComponent("battery-health.json")
        let pending = entries
        if let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Entry].self, from: data) { entries = saved }
        // Uma leitura feita antes de abrir o arquivo (o monitor começa primeiro) entra agora
        for e in pending {
            if entries.last?.day == e.day { entries[entries.count - 1] = e } else { entries.append(e) }
        }
        if !pending.isEmpty { save() }
    }

    /// Uma vez por dia basta (a saúde muda devagar)
    func update(_ h: BatteryHealth?, now: Date = Date()) {
        guard let health = h?.healthPercent, let cycles = h?.cycles else { return }
        let day = ScreenTime.dayKey(now)
        let entry = Entry(day: day, health: health, cycles: cycles)
        if entries.last?.day == day {
            guard entries.last != entry else { return }
            entries[entries.count - 1] = entry
        } else {
            entries.append(entry)
        }
        // Três anos de leituras diárias cabem em poucos KB
        if entries.count > 1100 { entries.removeFirst(entries.count - 1100) }
        save()
    }

    func set(_ demo: [Entry]) { entries = demo }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    struct Trend {
        var days: Int
        var healthChange: Int
        var cyclesPerMonth: Double
    }

    /// Precisa de pelo menos uma semana de leituras
    var trend: Trend? {
        guard let first = entries.first, let last = entries.last,
              let d0 = ScreenTime.date(fromKey: first.day), let d1 = ScreenTime.date(fromKey: last.day) else { return nil }
        let days = Int(d1.timeIntervalSince(d0) / 86_400)
        guard days >= 7 else { return nil }
        return Trend(days: days, healthChange: last.health - first.health,
                     cyclesPerMonth: Double(last.cycles - first.cycles) / Double(days) * 30)
    }

    /// Para os dados de exemplo das capturas de tela: 8 meses, de 100% a 96%
    static var demo: [Entry] {
        (0..<240).map { i in
            let d = Date().addingTimeInterval(-Double(239 - i) * 86_400)
            return Entry(day: ScreenTime.dayKey(d), health: 100 - i / 60, cycles: 40 + i * 72 / 240)
        }
    }
}

/// A linha do histórico no cartão da bateria
struct BatteryTrendRow: View {
    let entries: [BatteryLog.Entry]
    let trend: BatteryLog.Trend

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Histórico da saúde")).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(change).font(.system(size: 12, weight: .semibold))
                Text(L("~%d ciclos por mês", Int(trend.cyclesPerMonth.rounded()))).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            spark.frame(width: 120, height: 34)
        }
    }

    private var period: String {
        trend.days >= 60 ? L("%d meses", trend.days / 30) : L("%d dias", trend.days)
    }

    private var change: String {
        trend.healthChange == 0 ? L("Igual há %@", period)
            : L("%@%% em %@", trend.healthChange < 0 ? "−\(-trend.healthChange)" : "+\(trend.healthChange)", period)
    }

    private var spark: some View {
        GeometryReader { g in
            let vals = entries.map { Double($0.health) }
            let lo = (vals.min() ?? 0) - 1, hi = (vals.max() ?? 100) + 1
            let step = g.size.width / CGFloat(max(1, vals.count - 1))
            Path { p in
                for (i, v) in vals.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * step, y: g.size.height * (1 - CGFloat((v - lo) / max(1, hi - lo))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
            .stroke(Theme.battery, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}
