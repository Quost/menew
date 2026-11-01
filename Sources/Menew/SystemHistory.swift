import AppKit
import Charts
import SwiftUI

/// Histórico das últimas 24 horas: CPU, memória e bateria minuto a minuto, e quais apps mais gastaram energia
/// enquanto o Mac estava na bateria. Tudo fica num arquivo pequeno no Mac (Application Support/Menew).
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
            prune()
        }
    }

    private struct Saved: Codable {
        var samples: [Sample]
        var energy: [EnergyHour]
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
            if energy.last?.hour != hour { energy.append(EnergyHour(hour: hour, apps: [:])) }
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

    private func prune() {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        samples.removeAll { $0.t < cutoff }
        energy.removeAll { $0.hour < cutoff.addingTimeInterval(-3600) }
    }

    func save() {
        lastSave = Date()
        guard let url, let data = try? JSONEncoder().encode(Saved(samples: samples, energy: energy)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    enum Metric: Int { case cpu, memory, energy }

    /// Os 5 apps que mais usaram a métrica nas últimas 24 h: rótulo pronto e fração para a barra
    func top(_ metric: Metric) -> [(app: String, fraction: Double, label: String)] {
        var total: [String: Double] = [:]
        var samples = 0
        for h in energy {
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
        energy = [EnergyHour(hour: now, apps: ["Safari": 420, "Microsoft Teams": 310, "Xcode": 180, "Music": 60, "Mail": 25],
                             cpu: ["Xcode": 240, "Safari": 160, "Microsoft Teams": 120, "Figma": 60, "Mail": 10],
                             mem: ["Safari": 18_000, "Xcode": 14_000, "Microsoft Teams": 9_000, "Figma": 7_000, "Music": 2_000], n: 20)]
    }
}

/// Cartão "Últimas 24 horas" na aba Sistema
struct SystemHistoryCard: View {
    @ObservedObject var history = SystemHistory.shared
    @State private var metric = 0

    var body: some View {
        if history.samples.count >= 3 {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: L("Últimas 24 horas"), icon: "chart.xyaxis.line", color: .indigo) {
                    GlassSegmented(selection: $metric, options: options, expand: false)
                }
                Chart(history.samples) { s in
                    AreaMark(x: .value("t", s.t), y: .value("v", value(s)))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", s.t), y: .value("v", value(s)))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 9)) } } }
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
                .frame(height: 90)
                let kind: SystemHistory.Metric = metric == 0 ? .cpu : metric == 1 ? .memory : .energy
                let top = history.top(kind)
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
