import AppKit
import Charts
import SwiftUI

/// Histórico de CPU, memória e bateria: minuto a minuto nas últimas 24 horas e de hora em hora nos últimos 30 dias,
/// e quais apps mais usaram cada um. Tudo fica num arquivo pequeno no Mac (Application Support/Menew).
@MainActor
final class SystemHistory: ObservableObject {
    static let shared = SystemHistory()

    struct Sample: Codable, Identifiable {
        var id: Date { t }
        let t: Date
        let cpu: Double
        let mem: Double
        let battery: Int?
        let onAC: Bool?
    }

    /// Uso por app numa hora: energia (só na bateria), CPU e memória somadas a cada amostra; `n` = amostras
    struct EnergyHour: Codable {
        let hour: Date
        var apps: [String: Double]
        var cpu: [String: Double]? = nil
        var mem: [String: Double]? = nil
        var n: Int? = nil
    }

    @Published private(set) var samples: [Sample] = []
    @Published private(set) var energy: [EnergyHour] = []
    /// Médias por hora de tudo que já saiu da janela de 24 h (até 30 dias)
    @Published private(set) var hourly: [Sample] = []

    enum Range: Int, CaseIterable {
        case day, week, month
        var seconds: TimeInterval { switch self { case .day: 86_400; case .week: 7 * 86_400; case .month: 30 * 86_400 } }
        var title: String { switch self { case .day: "24h"; case .week: L("7 dias"); case .month: L("30 dias") } }
    }

    private var acc: (cpu: Double, mem: Double, n: Int) = (0, 0, 0)
    private var minute = -1
    private var lastEnergy = Date.distantPast
    private var sampling = false
    private var url: URL?
    private var lastSave = Date()

    func load(dir: URL) {
        url = dir.appendingPathComponent("system-history.json")
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            samples = saved.samples
            energy = saved.energy
            hourly = saved.hourly ?? []
            prune()
        }
    }

    private struct Saved: Codable {
        var samples: [Sample]
        var energy: [EnergyHour]
        var hourly: [Sample]?
    }

    /// Chamado a cada leitura do monitor (2 s); guarda a média de cada minuto
    func record(_ m: SystemMonitor) {
        acc.cpu += m.cpu
        acc.mem += m.memFraction
        acc.n += 1
        let now = Date()
        let min = Calendar.current.component(.minute, from: now)
        guard min != minute else { return }
        defer { minute = min; acc = (0, 0, 0) }
        guard minute != -1, acc.n > 0 else { return }
        samples.append(Sample(t: now, cpu: acc.cpu / Double(acc.n), mem: acc.mem / Double(acc.n),
                              battery: m.battery?.percent, onAC: m.battery?.onAC))
        prune()
        // Uso por app a cada 5 min (o `top` custa um pouco de CPU); energia só conta fora da tomada
        if now.timeIntervalSince(lastEnergy) >= 300 {
            lastEnergy = now
            sampleUsage(onBattery: m.battery?.onAC == false)
        }
        if now.timeIntervalSince(lastSave) >= 600 { save() }
    }

    private func sampleUsage(onBattery: Bool) {
        guard !sampling else { return }
        sampling = true
        Task {
            let (byCPU, byMem) = await Task.detached(priority: .background) {
                (Shell.run("/usr/bin/top", ["-l", "2", "-s", "1", "-n", "25", "-o", "cpu", "-stats", "pid,command,cpu,mem,power"]),
                 Shell.run("/usr/bin/top", ["-l", "1", "-n", "12", "-o", "mem", "-stats", "pid,command,cpu,mem,power"]))
            }.value
            sampling = false
            var cpu: [String: Double] = [:], power: [String: Double] = [:], mem: [String: Double] = [:]
            for p in Self.parseTop(byCPU) {
                let name = Self.appName(pid: p.pid, command: p.command)
                cpu[name, default: 0] += p.cpu
                power[name, default: 0] += p.power
            }
            for p in Self.parseTop(byMem, lastSample: false) { mem[Self.appName(pid: p.pid, command: p.command), default: 0] += p.memMB }
            guard !cpu.isEmpty || !mem.isEmpty else { return }
            let hour = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
            if energy.last?.hour != hour {
                // A hora anterior fechou: guarda só os apps que mais usaram, para o arquivo de 30 dias ficar pequeno
                if let last = energy.indices.last { energy[last] = Self.trimmed(energy[last]) }
                energy.append(EnergyHour(hour: hour, apps: [:]))
            }
            let i = energy.count - 1
            if onBattery { for (a, v) in power { energy[i].apps[a, default: 0] += v } }
            for (a, v) in cpu { energy[i].cpu = energy[i].cpu ?? [:]; energy[i].cpu?[a, default: 0] += v }
            for (a, v) in mem { energy[i].mem = energy[i].mem ?? [:]; energy[i].mem?[a, default: 0] += v }
            energy[i].n = (energy[i].n ?? 0) + 1
            prune()
        }
    }

    /// Nome do app (ajudantes como "Claude Helper (Renderer)" contam no app principal)
    static func appName(pid: Int32, command: String) -> String {
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? command
        return name.components(separatedBy: " Helper").first?.trimmingCharacters(in: .whitespaces) ?? name
    }

    struct TopRow { let pid: Int32; let command: String; let cpu: Double; let memMB: Double; let power: Double }

    /// Saída do `top -stats pid,command,cpu,mem,power`; com duas amostras, só a segunda vale (a primeira não tem CPU)
    nonisolated static func parseTop(_ out: String, lastSample: Bool = true) -> [TopRow] {
        let blocks = out.components(separatedBy: "COMMAND")
        guard blocks.count >= 2, let block = lastSample ? blocks.last : blocks[1] as String? else { return [] }
        var result: [TopRow] = []
        for line in block.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5, let pid = Int32(parts[0]), let power = Double(parts[parts.count - 1]),
                  let cpu = Double(parts[parts.count - 3]) else { continue }
            let name = parts[1..<(parts.count - 3)].joined(separator: " ")
            guard !["top", "kernel_task"].contains(name) else { continue }
            result.append(TopRow(pid: pid, command: name, cpu: cpu, memMB: memory(String(parts[parts.count - 2])), power: power))
        }
        return result
    }

    /// "875M", "21M+", "5872K-", "1.2G" → MB
    nonisolated static func memory(_ s: String) -> Double {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard let unit = t.last, let n = Double(t.dropLast()) else { return 0 }
        switch unit {
        case "K": return n / 1024
        case "M": return n
        case "G": return n * 1024
        default: return Double(t) ?? 0
        }
    }

    static func trimmed(_ h: EnergyHour, keep: Int = 15) -> EnergyHour {
        func top(_ d: [String: Double]?) -> [String: Double]? {
            d.map { Dictionary(uniqueKeysWithValues: $0.sorted { $0.value > $1.value }.prefix(keep).map { ($0.key, $0.value) }) }
        }
        return EnergyHour(hour: h.hour, apps: top(h.apps) ?? [:], cpu: top(h.cpu), mem: top(h.mem), n: h.n)
    }

    /// Médias de hora em hora (a última amostra de bateria de cada hora)
    static func hourlyAverages(_ list: [Sample]) -> [Sample] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: list) { cal.dateInterval(of: .hour, for: $0.t)?.start ?? $0.t }
        return groups.keys.sorted().map { h in
            let g = groups[h]!.sorted { $0.t < $1.t }
            return Sample(t: h.addingTimeInterval(1800), cpu: g.map(\.cpu).reduce(0, +) / Double(g.count),
                          mem: g.map(\.mem).reduce(0, +) / Double(g.count), battery: g.last?.battery, onAC: g.last?.onAC)
        }
    }

    func prune(now: Date = Date()) {
        // Corta em hora cheia, para cada hora virar uma média inteira
        let cutoff = Calendar.current.dateInterval(of: .hour, for: now.addingTimeInterval(-24 * 3600))?.start ?? now
        let old = samples.filter { $0.t < cutoff }
        if !old.isEmpty {
            let last = hourly.last?.t ?? .distantPast
            hourly += Self.hourlyAverages(old).filter { $0.t > last }
            samples.removeAll { $0.t < cutoff }
        }
        let month = now.addingTimeInterval(-Range.month.seconds)
        hourly.removeAll { $0.t < month }
        energy.removeAll { $0.hour < month.addingTimeInterval(-3600) }
    }

    /// Pontos do gráfico: minuto a minuto em 24 h; de hora em hora em 7 e 30 dias
    func series(_ range: Range, now: Date = Date()) -> [Sample] {
        guard range != .day else { return samples }
        let from = now.addingTimeInterval(-range.seconds)
        return (hourly + Self.hourlyAverages(samples)).filter { $0.t >= from }
    }

    func save() {
        lastSave = Date()
        // O de hora em hora também: sem ele, os gráficos de 7 e 30 dias recomeçavam a cada abertura
        guard let url, let data = try? JSONEncoder().encode(Saved(samples: samples, energy: energy, hourly: hourly)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    enum Metric: Int { case cpu, memory, energy }

    /// Os 5 apps que mais usaram a métrica no período: rótulo pronto e fração para a barra
    func top(_ metric: Metric, range: Range = .day, now: Date = Date()) -> [(app: String, fraction: Double, label: String)] {
        var total: [String: Double] = [:]
        var samples = 0
        let from = now.addingTimeInterval(-range.seconds - 3600)
        for h in energy where h.hour >= from {
            let dict = metric == .energy ? h.apps : metric == .cpu ? (h.cpu ?? [:]) : (h.mem ?? [:])
            for (a, v) in dict { total[a, default: 0] += v }
            samples += h.n ?? 0
        }
        let sorted = total.sorted { $0.value > $1.value }.prefix(5)
        guard let max = sorted.first?.value, max > 0 else { return [] }
        switch metric {
        case .energy:
            let sum = total.values.reduce(0, +)
            return sorted.map { ($0.key, $0.value / max, "\(Int((($0.value / sum) * 100).rounded()))%") }
        case .cpu:
            let n = Double(Swift.max(samples, 1))
            return sorted.map { ($0.key, $0.value / max, "\(Int(($0.value / n).rounded()))%") }
        case .memory:
            let n = Double(Swift.max(samples, 1))
            return sorted.map { ($0.key, $0.value / max, Fmt.bytes(Int64($0.value / n * 1_048_576))) }
        }
    }

    /// Para as capturas de tela: um dia inventado
    func showDemo() {
        let now = Date()
        samples = (0..<288).map { i in
            let t = now.addingTimeInterval(Double(i - 288) * 300)
            let wave = sin(Double(i) / 18)
            return Sample(t: t, cpu: max(0.04, 0.18 + 0.12 * wave + (i % 37 == 0 ? 0.4 : 0)), mem: 0.55 + 0.08 * sin(Double(i) / 40),
                          battery: max(20, 100 - i / 4), onAC: i > 250)
        }
        hourly = (24..<(30 * 24)).reversed().map { h in
            let t = now.addingTimeInterval(-Double(h) * 3600)
            let day = Calendar.current.component(.hour, from: t)
            let busy = (9...18).contains(day) ? 0.22 : 0.06
            return Sample(t: t, cpu: busy + 0.05 * sin(Double(h) / 7), mem: 0.5 + 0.1 * sin(Double(h) / 50), battery: 40 + (h * 7) % 60, onAC: nil)
        }
        energy = [EnergyHour(hour: now, apps: ["Safari": 420, "Microsoft Teams": 310, "Xcode": 180, "Music": 60, "Mail": 25],
                             cpu: ["Xcode": 240, "Safari": 160, "Microsoft Teams": 120, "Figma": 60, "Mail": 10],
                             mem: ["Safari": 18_000, "Xcode": 14_000, "Microsoft Teams": 9_000, "Figma": 7_000, "Music": 2_000], n: 20)]
    }
}

/// Cartão "Histórico" na aba Sistema
struct SystemHistoryCard: View {
    @ObservedObject var history = SystemHistory.shared
    @State private var metric = 0
    @AppStorage("historyRange") private var rangeRaw = 0
    private var range: SystemHistory.Range { SystemHistory.Range(rawValue: rangeRaw) ?? .day }

    var body: some View {
        if history.samples.count >= 3 {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: L("Histórico"), icon: "chart.xyaxis.line", color: .indigo) {
                    GlassSegmented(selection: $metric, options: options, expand: false)
                }
                GlassSegmented(selection: $rangeRaw, options: SystemHistory.Range.allCases.map { .init(value: $0.rawValue, title: $0.title) })
                let points = history.series(range)
                Chart(points) { s in
                    AreaMark(x: .value("t", s.t), y: .value("v", value(s)))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", s.t), y: .value("v", value(s)))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 9)) } } }
                .chartXAxis {
                    switch range {
                    case .day: AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisValueLabel(format: .dateTime.hour()) }
                    case .week: AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) }
                    case .month: AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
                    }
                }
                .frame(height: 90)
                let kind: SystemHistory.Metric = metric == 0 ? .cpu : metric == 1 ? .memory : .energy
                let top = history.top(kind, range: range)
                Text(kind == .cpu ? L("Mais usaram CPU") : kind == .memory ? L("Mais usaram memória") : L("Mais gastaram bateria"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 2)
                if top.isEmpty {
                    Text(kind == .energy ? L("Aparece depois de um tempo usando o Mac na bateria.") : L("Aparece depois de alguns minutos de uso."))
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                ForEach(top, id: \.app) { e in
                    HStack(spacing: 8) {
                        Text(e.app).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 4)
                        GeometryReader { g in
                            Capsule().fill(color.opacity(0.7)).frame(width: max(4, g.size.width * e.fraction))
                        }
                        .frame(width: 80, height: 6)
                        Text(e.label).font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
                    }
                }
            }
            .card(padding: 14)
        }
    }

    private var options: [GlassSegmented<Int>.Option] {
        var o: [GlassSegmented<Int>.Option] = [.init(value: 0, icon: "cpu", help: "CPU"), .init(value: 1, icon: "memorychip", help: L("Memória"))]
        if history.samples.contains(where: { $0.battery != nil }) { o.append(.init(value: 2, icon: "battery.75percent", help: L("Bateria"))) }
        return o
    }

    private var color: Color { metric == 0 ? Theme.cpu : metric == 1 ? Theme.memory : Theme.battery }

    private func value(_ s: SystemHistory.Sample) -> Double {
        switch metric {
        case 0: s.cpu * 100
        case 1: s.mem * 100
        default: Double(s.battery ?? 0)
        }
    }
}

/// Últimas 24 horas de uma métrica, com os apps que mais pesaram: o "gráfico" de cada painel da barra de menus
struct HistoryMini: View {
    @ObservedObject var history = SystemHistory.shared
    let metric: SystemHistory.Metric

    private var color: Color { metric == .cpu ? Theme.cpu : metric == .memory ? Theme.memory : Theme.battery }

    private func value(_ s: SystemHistory.Sample) -> Double? {
        switch metric {
        case .cpu: s.cpu * 100
        case .memory: s.mem * 100
        case .energy: s.battery.map(Double.init)
        }
    }

    var body: some View {
        let points = history.samples.compactMap { s in value(s).map { (s.t, $0) } }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Últimas 24 horas")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if let avg = points.isEmpty ? nil : points.map(\.1).reduce(0, +) / Double(points.count), metric != .energy {
                    Text(L("média %@", "\(Int(avg.rounded()))%")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            if points.count < 3 {
                Text(L("Aparece depois de alguns minutos de uso.")).font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                Chart(points, id: \.0) { p in
                    AreaMark(x: .value("t", p.0), y: .value("v", p.1))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", p.0), y: .value("v", p.1)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 9)) } } }
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
                .frame(height: 70)
            }
            let top = history.top(metric).prefix(3)
            if !top.isEmpty {
                Text(metric == .cpu ? L("Mais usaram CPU") : metric == .memory ? L("Mais usaram memória") : L("Mais gastaram bateria"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 2)
                ForEach(Array(top), id: \.app) { e in
                    HStack(spacing: 8) {
                        Text(e.app).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(e.label).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card(padding: 14)
    }
}
