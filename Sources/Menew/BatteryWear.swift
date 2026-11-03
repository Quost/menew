import Charts
import SwiftUI

/// Onde a bateria se desgasta: quanto saiu dela fora da tomada (100% = 1 ciclo), em que hora do dia,
/// e o que desgasta mesmo sem somar ciclos (calor, tomada acima de 95%, descer abaixo de 20%).
/// Um resumo por dia num arquivo pequeno no Mac; os apps vêm do consumo por app que o histórico já mede.
@MainActor
final class BatteryWear: ObservableObject {
    static let shared = BatteryWear()

    struct Day: Codable, Equatable, Identifiable {
        var id: String { day }
        var day: String
        /// Pontos percentuais que saíram fora da tomada (100 = 1 ciclo)
        var used: Double = 0
        /// O mesmo, por hora do dia (0…23)
        var hours: [Double] = Array(repeating: 0, count: 24)
        /// Minutos com a bateria a 35 °C ou mais
        var hot: Int = 0
        /// Minutos na tomada com 95% ou mais
        var full: Int = 0
        /// Vezes que desceu abaixo de 20% fora da tomada
        var low: Int = 0

        var cycles: Double { used / 100 }
    }

    @Published private(set) var days: [Day] = []
    private var last: (t: Date, percent: Int, onAC: Bool)?
    private var url: URL?
    private var lastSave = Date()

    static let hotLimit = 35.0
    static let fullLimit = 95
    static let lowLimit = 20

    func load(dir: URL) {
        url = dir.appendingPathComponent("battery-wear.json")
        if let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Day].self, from: data) { days = saved }
    }

    /// Chamado a cada leitura do monitor; conta de minuto em minuto
    func record(_ b: BatteryInfo?, _ h: BatteryHealth?, now: Date = Date()) {
        guard let b else { return }
        guard let prev = last else { last = (now, b.percent, b.onAC); return }
        let dt = now.timeIntervalSince(prev.t)
        guard dt >= 60 else { return }
        last = (now, b.percent, b.onAC)
        let key = ScreenTime.dayKey(now)
        if days.last?.day != key { days.append(Day(day: key)) }
        let i = days.count - 1
        // Mac dormindo: a carga que caiu conta, mas o tempo parado não vira minutos de calor ou de tomada
        let minutes = Int(min(dt, 300) / 60)
        // Toda carga que sai conta para o ciclo, até na tomada com carregador fraco e o Mac pesado
        let drop = prev.percent - b.percent
        if drop > 0 {
            days[i].used += Double(drop)
            days[i].hours[Calendar.current.component(.hour, from: now)] += Double(drop)
        }
        if !b.onAC, prev.percent >= Self.lowLimit, b.percent < Self.lowLimit { days[i].low += 1 }
        if let t = h?.temperature, t >= Self.hotLimit { days[i].hot += minutes }
        if b.onAC, b.percent >= Self.fullLimit { days[i].full += minutes }
        // Um ano de dias cabe em poucos KB
        if days.count > 400 { days.removeFirst(days.count - 400) }
        if now.timeIntervalSince(lastSave) >= 600 { save() }
    }

    func save() {
        lastSave = Date()
        guard let url, let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Contas

    /// Os últimos `n` dias, do mais antigo ao de hoje (dias sem leitura entram zerados)
    func recent(_ n: Int, now: Date = Date()) -> [Day] {
        let byKey = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { $1 })
        return (0..<n).reversed().map { back in
            let key = ScreenTime.dayKey(Calendar.current.date(byAdding: .day, value: -back, to: now) ?? now)
            return byKey[key] ?? Day(day: key)
        }
    }

    struct Summary {
        var week: Double
        var previousWeek: Double
        var perMonth: Double
        /// Horas do dia (0…23) somadas nos últimos 30 dias
        var hours: [Double]
        var peakHour: Int?
        var hotMinutes: Int
        var fullMinutes: Int
        var lowCount: Int
        var daysWithData: Int
    }

    func summary(now: Date = Date()) -> Summary {
        let month = recent(30, now: now)
        let week = month.suffix(7), before = month.dropLast(7).suffix(7)
        var hours = Array(repeating: 0.0, count: 24)
        for d in month { for h in 0..<24 where h < d.hours.count { hours[h] += d.hours[h] } }
        let withData = month.filter { $0.used > 0 || $0.hot > 0 || $0.full > 0 }.count
        let peak = hours.max().flatMap { m in m > 0 ? hours.firstIndex(of: m) : nil }
        return Summary(week: week.map(\.cycles).reduce(0, +), previousWeek: before.map(\.cycles).reduce(0, +),
                       perMonth: month.map(\.cycles).reduce(0, +) / Double(max(withData, 1)) * 30,
                       hours: hours, peakHour: peak,
                       hotMinutes: week.map(\.hot).reduce(0, +), fullMinutes: week.map(\.full).reduce(0, +),
                       lowCount: week.map(\.low).reduce(0, +), daysWithData: withData)
    }

    // MARK: Capturas de tela

    func showDemo(now: Date = Date()) {
        days = (0..<30).reversed().map { back in
            let date = Calendar.current.date(byAdding: .day, value: -back, to: now) ?? now
            let weekday = Calendar.current.component(.weekday, from: date)
            let workday = (2...6).contains(weekday)
            var d = Day(day: ScreenTime.dayKey(date))
            // Mais uso à tarde nos dias de semana, um pouco à noite no fim de semana
            for h in 0..<24 {
                let base = workday ? ((13...17).contains(h) ? 9.0 : (9...12).contains(h) ? 4.0 : 0) : ((20...23).contains(h) ? 6.0 : 0)
                d.hours[h] = base * (0.7 + 0.6 * abs(sin(Double(back * 7 + h))))
            }
            d.used = d.hours.reduce(0, +)
            d.hot = workday ? 40 + (back * 13) % 50 : 5
            d.full = workday ? 180 : 420
            d.low = back % 9 == 0 ? 1 : 0
            return d
        }
    }
}

/// O cartão "Desgaste" na seção Bateria da janela Menew
struct BatteryWearCard: View {
    @ObservedObject var wear = BatteryWear.shared
    @ObservedObject var history = SystemHistory.shared

    var body: some View {
        let s = wear.summary()
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: L("Desgaste"), icon: "bolt.batteryblock", color: Theme.battery) {
                Text(L("Últimos 30 dias")).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            if s.daysWithData == 0 {
                Text(L("Começa a contar agora: conforme você usa o Mac fora da tomada, aparecem aqui os ciclos de cada dia, as horas que mais gastam e os apps."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                headline(s)
                cyclesChart
                Divider()
                hoursStrip(s)
                Divider()
                apps
                Divider()
                stress(s)
            }
        }
        .card()
    }

    // Quanto: ciclos da semana e comparação
    private func headline(_ s: BatteryWear.Summary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Esta semana")).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(L("%@ ciclos", Self.fmt(s.week))).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(L("No ritmo de")).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(L("~%d por mês", Int(s.perMonth.rounded()))).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
            if s.previousWeek > 0.05 {
                let change = (s.week - s.previousWeek) / s.previousWeek
                Text(L("%@ que a semana passada", change >= 0 ? "+\(Int((change * 100).rounded()))%" : "−\(Int((-change * 100).rounded()))%"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(change > 0.15 ? .orange : .secondary)
            }
        }
    }

    // Quando: ciclos por dia
    private var cyclesChart: some View {
        let list = wear.recent(30)
        return Chart(list) { d in
            BarMark(x: .value("dia", ScreenTime.date(fromKey: d.day) ?? Date(), unit: .day), y: .value("ciclos", d.cycles))
                .foregroundStyle(Theme.battery.gradient)
                .cornerRadius(2)
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        .frame(height: 110)
        .accessibilityLabel(L("Ciclos por dia nos últimos 30 dias"))
    }

    // Em que hora do dia mais gasta
    private func hoursStrip(_ s: BatteryWear.Summary) -> some View {
        let mx = max(s.hours.max() ?? 0, 0.01)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Horas que mais gastam")).font(.system(size: 11, weight: .semibold))
                Spacer()
                if let p = s.peakHour {
                    Text(L("pico entre %dh e %dh", p, (p + 1) % 24)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.battery.opacity(0.12 + 0.88 * s.hours[h] / mx))
                        .frame(height: 16)
                        .help(L("%dh: %@ ciclos em 30 dias", h, Self.fmt(s.hours[h] / 100)))
                }
            }
            HStack {
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text("\(h)h").font(.system(size: 9)).foregroundStyle(.tertiary)
                    if h != 18 { Spacer() }
                }
                Spacer()
                Text("23h").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    // O que: apps que mais gastaram fora da tomada
    private var apps: some View {
        let top = history.top(.energy, range: .week)
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("Apps que mais gastaram fora da tomada (7 dias)")).font(.system(size: 11, weight: .semibold))
            if top.isEmpty {
                Text(L("Aparece depois de usar o Mac fora da tomada.")).font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                ForEach(top, id: \.app) { row in
                    HStack(spacing: 8) {
                        Text(row.app).font(.system(size: 11.5)).lineLimit(1).frame(width: 130, alignment: .leading)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3).fill(Theme.battery.gradient).frame(width: max(3, g.size.width * row.fraction))
                        }
                        .frame(height: 8)
                        Text(row.label).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit().frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    // O que desgasta sem somar ciclos
    private func stress(_ s: BatteryWear.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Também desgasta (7 dias)")).font(.system(size: 11, weight: .semibold))
            HStack(alignment: .top, spacing: 0) {
                stat(L("Quente (35 °C ou mais)"), Self.duration(s.hotMinutes), warn: s.hotMinutes >= 300)
                stat(L("Na tomada acima de 95%"), Self.duration(s.fullMinutes), warn: s.fullMinutes >= 7 * 600)
                stat(L("Abaixo de 20%"), L("%d vezes", s.lowCount), warn: s.lowCount >= 3)
            }
            if let tip = tip(s) {
                Label(tip, systemImage: "lightbulb").font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stat(_ title: String, _ value: String, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(warn ? .orange : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Uma dica só, a do que mais pesou
    private func tip(_ s: BatteryWear.Summary) -> String? {
        if s.hotMinutes >= 300 { return L("Calor é o que mais desgasta: deixe as saídas de ar livres e evite carregar no sol ou em cima de cobertas.") }
        if s.fullMinutes >= 7 * 600 { return L("Passa muito tempo cheia na tomada: ligue o Carregamento Otimizado em Ajustes do Sistema › Bateria.") }
        if s.lowCount >= 3 { return L("Descer abaixo de 20% com frequência cansa a bateria: carregue um pouco antes.") }
        return nil
    }

    static func fmt(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(v < 10 ? 1 : 0)).locale(L10n.locale))
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}
