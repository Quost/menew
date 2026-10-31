import AppKit
import SwiftUI

struct ListeningPort: Identifiable, Hashable {
    let pid: Int32
    let command: String
    let port: Int
    var id: String { "\(pid):\(port)" }

    /// Nome do app quando é um (Docker, Postgres.app), senão o comando (node, python3)
    @MainActor var name: String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? command
    }
}

/// Servidores escutando em portas TCP deste Mac (os seus processos; os do sistema exigiriam senha).
/// Lido com o `lsof` só quando você abre a lista ou a paleta.
@MainActor
final class Ports: ObservableObject {
    static let shared = Ports()
    @Published private(set) var list: [ListeningPort] = []
    private var loading = false
    var onChange: (() -> Void)?

    func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            let found = await Task.detached { Self.read() }.value
            loading = false
            if found != list { list = found; onChange?() }
        }
    }

    func stop(_ p: ListeningPort) {
        let name = p.name
        if kill(p.pid, SIGTERM) == 0 {
            HUD.show(icon: "stop.circle.fill", color: .red, text: L("%@ parado (porta %d)", name, p.port))
        } else {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para parar %@", name))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }
    }

    nonisolated private static func read() -> [ListeningPort] {
        let out = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"])
        var result: [ListeningPort] = []
        var seen = Set<String>()
        var pid: Int32 = 0, cmd = ""
        for line in out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": cmd = String(value)
            case "n":
                // "*:3000", "127.0.0.1:5432", "[::1]:8080"
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                if seen.insert("\(pid):\(port)").inserted { result.append(ListeningPort(pid: pid, command: cmd, port: port)) }
            default: break
            }
        }
        return result.sorted { $0.port < $1.port }
    }
}
