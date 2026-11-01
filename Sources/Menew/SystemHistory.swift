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

    /// Consumo por app numa hora (índice de energia do `top`, somado a cada amostra)
    struct EnergyHour: Codable {
        let hour: Date
        var apps: [String: Double]
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
        // Energia por app: a cada 5 min, só na bateria (o `top` custa um pouco de CPU)
        if m.battery?.onAC == false, now.timeIntervalSince(lastEnergy) >= 300 {
            lastEnergy = now
            sampleEnergy()
        }
        if now.timeIntervalSince(lastSave) >= 600 { save() }
    }

    private func sampleEnergy() {
        guard !sampling else { return }
        sampling = true
        Task {
            let out = await Task.detached(priority: .background) {
                Shell.run("/usr/bin/top", ["-l", "2", "-s", "1", "-n", "10", "-o", "power", "-stats", "pid,command,power"])
            }.value
            sampling = false
            // O `top` corta nomes em 16 letras: o nome do app vem do processo, quando é um app
            var found: [String: Double] = [:]
            for (pid, command, power) in Self.parseTop(out) {
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? command
                found[name, default: 0] += power
            }
            guard !found.isEmpty else { return }
            let hour = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
            if energy.last?.hour != hour { energy.append(EnergyHour(hour: hour, apps: [:])) }
            for (app, power) in found { energy[energy.count - 1].apps[app, default: 0] += power }
            prune()
        }
    }

    /// Segunda amostra do `top` (a primeira não tem consumo): "123  Safari  12.3"
    nonisolated static func parseTop(_ out: String) -> [(pid: Int32, command: String, power: Double)] {
        let blocks = out.components(separatedBy: "COMMAND")
        guard blocks.count >= 3, let last = blocks.last else { return [] }
        var result: [(Int32, String, Double)] = []
        for line in last.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]), let power = Double(parts.last!), power > 0 else { continue }
            let name = parts.dropFirst().dropLast().joined(separator: " ")
            guard !["top", "kernel_task", "WindowServer"].contains(name) else { continue }
            result.append((pid, name, power))
        }
        return result
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

    /// Os apps que mais gastaram energia nas últimas 24 h, em % do total
    var topEnergy: [(app: String, share: Double)] {
        var total: [String: Double] = [:]
        for h in energy { for (a, v) in h.apps { total[a, default: 0] += v } }
        let sum = total.values.reduce(0, +)
        guard sum > 0 else { return [] }
        return total.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value / sum) }
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
        energy = [EnergyHour(hour: now, apps: ["Safari": 420, "Microsoft Teams": 310, "Xcode": 180, "Music": 60, "Mail": 25])]
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
                let top = history.topEnergy
                if !top.isEmpty {
                    Text(L("Mais gastaram bateria")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 2)
                    ForEach(top, id: \.app) { e in
                        HStack(spacing: 8) {
                            Text(e.app).font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 4)
                            GeometryReader { g in
                                Capsule().fill(Color.orange.opacity(0.7)).frame(width: max(4, g.size.width * e.share))
                            }
                            .frame(width: 80, height: 6)
                            Text("\(Int((e.share * 100).rounded()))%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                        }
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
