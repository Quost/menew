import AppKit

/// Alerta de app descontrolado: um processo acima de 90% da CPU por ~6 minutos seguidos ganha um aviso
/// (no máximo um por hora para o mesmo app). Desligado por padrão, como os outros alertas.
@MainActor
final class RunawayWatch {
    static let shared = RunawayWatch()
    static let key = "alertRunaway"
    private var timer: Timer?
    private var streak: [Int32: Int] = [:]
    private var warned: [String: Date] = [:]

    func refresh() {
        let on = UserDefaults.standard.bool(forKey: Self.key)
        if on, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
                MainActor.assumeIsolated { RunawayWatch.shared.check() }
            }
            timer?.tolerance = 20
        } else if !on {
            timer?.invalidate(); timer = nil; streak = [:]
        }
    }

    private func check() {
        Task {
            let out = await Task.detached(priority: .background) { Shell.run("/bin/ps", ["-Aceo", "pid,pcpu,comm", "-r"]) }.value
            let hot = Self.parse(out).filter { $0.cpu >= 90 }
            streak = Dictionary(uniqueKeysWithValues: hot.map { ($0.pid, (streak[$0.pid] ?? 0) + 1) })
            for p in hot where (streak[p.pid] ?? 0) >= 3 {
                let name = SystemHistory.appName(pid: p.pid, command: p.command)
                if let last = warned[name], Date().timeIntervalSince(last) < 3600 { continue }
                warned[name] = Date()
                Alerts.shared.notify(id: "runaway.\(name)", title: L("%@ está pesando no Mac", name),
                                     body: L("Usando %d%% da CPU há uns %d minutos. Se travou, encerre pela aba Sistema.", Int(p.cpu), (streak[p.pid] ?? 3) * 2))
            }
        }
    }

    /// Saída do `ps -Aceo pid,pcpu,comm -r`: os 8 primeiros processos (já ordenados por CPU)
    nonisolated static func parse(_ out: String) -> [(pid: Int32, cpu: Double, command: String)] {
        out.split(separator: "\n").dropFirst().prefix(8).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else { return nil }
            let cmd = String(parts[2])
            return cmd == "kernel_task" ? nil : (pid, cpu, cmd)
        }
    }
}
