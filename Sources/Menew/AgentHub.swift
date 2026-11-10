import AppKit
import Darwin
import SwiftUI

/// Central de agentes: quais Claude Code, Codex e Gemini estão rodando, quais estão trabalhando, quais terminaram e
/// quais esperam por você (uma permissão, uma pergunta). Os próprios CLIs avisam o Menew por hooks: um comando que eles
/// rodam a cada evento (`Menew --agent-hook claude`), que passa o recado ao Menew aberto por uma notificação local do
/// macOS e sai. Nada sai do Mac.

// MARK: O comando que os CLIs rodam

enum AgentHookCommand {
    static let notification = Notification.Name("com.matheusquost.menew.agent")
    static let flag = "--agent-hook"

    /// Lê o evento (JSON na entrada), descobre o terminal e o processo do agente, avisa o Menew e sai.
    /// Não escreve nada na saída: no Claude Code, o que um hook imprime em alguns eventos vira contexto da conversa.
    static func run(agent: String) -> Never {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        var info: [String: String] = ["agent": agent]
        info["event"] = obj["hook_event_name"] as? String ?? CommandLine.arguments.last
        info["session"] = obj["session_id"] as? String
        info["cwd"] = obj["cwd"] as? String ?? FileManager.default.currentDirectoryPath
        info["message"] = (obj["message"] as? String).map { String($0.prefix(200)) }
        info["kind"] = obj["notification_type"] as? String
        info["step"] = step(obj)
        info["prompt"] = (obj["prompt"] as? String).map { oneLine($0, 140) }
        let chain = ProcessTree.ancestors(of: getppid())
        if let agentPID = chain.first(where: { AgentProcesses.matches(ProcessTree.name($0), agent: agent) }) {
            info["pid"] = String(agentPID)
        }
        // O primeiro app de verdade acima do agente é o terminal (Terminal, iTerm, Ghostty, VS Code, Cursor…)
        if let app = chain.lazy.compactMap({ NSRunningApplication(processIdentifier: $0) }).first(where: { $0.activationPolicy == .regular }) {
            info["app"] = app.bundleIdentifier
            info["appPID"] = String(app.processIdentifier)
        }
        DistributedNotificationCenter.default().postNotificationName(notification, object: nil, userInfo: info, deliverImmediately: true)
        exit(0)
    }
}

extension AgentHookCommand {
    /// O passo em poucas palavras: "Edit · AgentsView.swift", "Bash · Rodar os testes", "Grep · TODO"
    static func step(_ obj: [String: Any]) -> String? {
        guard let tool = obj["tool_name"] as? String, !tool.isEmpty else { return nil }
        let input = obj["tool_input"] as? [String: Any] ?? [:]
        var detail: String?
        if let f = (input["file_path"] ?? input["path"] ?? input["notebook_path"]) as? String, !f.isEmpty {
            detail = URL(fileURLWithPath: f).lastPathComponent
        } else {
            detail = ["description", "command", "cmd", "pattern", "url", "query", "prompt"].lazy
                .compactMap { input[$0] as? String }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            // O Codex passa o comando como lista: ["bash", "-lc", "swift test"]
            if detail == nil, let parts = input["command"] as? [String] { detail = parts.last }
        }
        // mcp__menew__search_notes → menew · search_notes
        let name = tool.hasPrefix("mcp__") ? tool.dropFirst(5).replacingOccurrences(of: "__", with: " · ") : tool
        return detail.map { "\(name) · \(oneLine($0, 80))" } ?? name
    }

    static func oneLine(_ s: String, _ max: Int) -> String {
        let t = s.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return t.count > max ? String(t.prefix(max - 1)) + "…" : t
    }
}

/// Processos: o pai de cada um, o nome e a pasta onde está rodando
enum ProcessTree {
    static func parent(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let p = info.kp_eproc.e_ppid
        return p > 1 ? p : nil
    }

    /// O próprio processo e os de cima, até o launchd
    static func ancestors(of pid: pid_t) -> [pid_t] {
        var out: [pid_t] = []
        var cur: pid_t? = pid
        while let p = cur, out.count < 24 {
            out.append(p)
            cur = parent(p)
        }
        return out
    }

    static func name(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 1024)
        proc_name(pid, &buf, UInt32(buf.count))
        return String(cString: buf)
    }

    static func cwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    static func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
}

/// Os agentes rodando agora, pela lista de processos (para quem ainda não ligou os hooks)
enum AgentProcesses {
    static func matches(_ name: String, agent: String) -> Bool {
        let n = name.lowercased()
        switch agent {
        case "claude": return n == "claude"
        case "codex": return n == "codex" || n.hasPrefix("codex-")
        case "gemini": return n == "gemini" || n == "node"
        default: return false
        }
    }

    struct Found { let agent: AgentKind; let pid: pid_t; let cwd: String? }

    /// `ps` com os argumentos: o Gemini roda como `node …/gemini`; o servidor do Codex e os de MCP não contam
    static func list() -> [Found] {
        let out = Shell.run("/bin/ps", ["-axww", "-o", "pid=,args="])
        return parse(out).map { Found(agent: $0.0, pid: $0.1, cwd: ProcessTree.cwd($0.1)) }
    }

    static func parse(_ ps: String) -> [(AgentKind, pid_t)] {
        ps.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let sp = t.firstIndex(of: " "), let pid = pid_t(t[..<sp]) else { return nil }
            let args = t[sp...].trimmingCharacters(in: .whitespaces)
            let parts = args.split(separator: " ")
            guard let exe = parts.first.map({ String($0.split(separator: "/").last ?? "") }) else { return nil }
            let rest = parts.dropFirst().map(String.init)
            if rest.contains(where: { ["app-server", "mcp", "mcp-server", AgentHookCommand.flag, "--mcp"].contains($0) }) { return nil }
            switch exe {
            case "claude": return (.claude, pid)
            case "codex": return (.codex, pid)
            case "gemini": return (.gemini, pid)
            case "node":
                // node /opt/homebrew/bin/gemini …
                if let script = rest.first, script.hasSuffix("/gemini") || script.hasSuffix("gemini-cli/dist/index.js") { return (.gemini, pid) }
                return nil
            default: return nil
            }
        }
    }
}

// MARK: Sessões

struct AgentSession: Identifiable, Equatable {
    enum State: String { case working, waiting, done, idle, running }

    var id: String
    var agent: AgentKind
    var cwd: String?
    var state: State
    var since: Date
    /// Quando começou o pedido atual (para dizer quanto tempo levou)
    var turnStart: Date?
    var message: String?
    /// O que você pediu (a primeira linha do prompt) e o passo de agora (a última ferramenta)
    var task: String?
    var step: String?
    var appBundle: String?
    var appPID: pid_t?
    var pid: pid_t?
    var updated: Date
    /// Veio dos hooks (sabe o estado) ou só da lista de processos (sabe que está rodando)
    var fromHooks = true

    var project: String { AgentDates.project(cwd) }

    var stateTitle: String {
        switch state {
        case .working: L("Trabalhando")
        case .waiting: L("Esperando você")
        case .done: L("Terminou")
        case .idle: L("Parado")
        case .running: L("Rodando")
        }
    }

    var stateColor: Color {
        switch state {
        case .working: .blue
        case .waiting: .orange
        case .done: .green
        case .idle, .running: .secondary
        }
    }
}

@MainActor
final class AgentHub: ObservableObject {
    static let shared = AgentHub()
    static let notifyKey = "agents.notify"
    /// Avisar quando um pedido que levou mais que isso termina
    static let doneAfter: TimeInterval = 20

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var processes: [AgentProcesses.Found] = []
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var demo = false
    var isVisible = false { didSet { if isVisible { scanProcesses() } } }

    var working: Int { sessions.filter { $0.state == .working }.count }

    /// Para o painel do notch: quem espera, quem trabalha e quem terminou há pouco (até 15 min)
    func active(now: Date = Date()) -> [AgentSession] {
        let order: [AgentSession.State] = [.waiting, .working, .done]
        return sessions.filter { $0.state == .waiting || $0.state == .working || ($0.state == .done && now.timeIntervalSince($0.updated) < 900) }
            .sorted { (order.firstIndex(of: $0.state) ?? 9, $1.updated) < (order.firstIndex(of: $1.state) ?? 9, $0.updated) }
    }
    var waiting: Int { sessions.filter { $0.state == .waiting }.count }

    /// Tudo o que aparece na lista: as sessões dos hooks e, das ferramentas sem hooks, os processos rodando
    var visible: [AgentSession] {
        let known = Set(sessions.compactMap(\.pid))
        let extra = processes.filter { !known.contains($0.pid) && AgentHooks.status($0.agent) != .installed }.map {
            AgentSession(id: "pid.\($0.pid)", agent: $0.agent, cwd: $0.cwd, state: .running, since: Date(), pid: $0.pid, updated: Date(), fromHooks: false)
        }
        let order: [AgentSession.State] = [.waiting, .working, .done, .running, .idle]
        return (sessions + extra).sorted {
            (order.firstIndex(of: $0.state)!, $1.updated) < (order.firstIndex(of: $1.state)!, $0.updated)
        }
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: AgentHookCommand.notification, object: nil, queue: .main) { n in
            let info = (n.userInfo as? [String: String]) ?? [:]
            MainActor.assumeIsolated { AgentHub.shared.handle(info) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated { AgentHub.shared.prune() }
        }
        timer?.tolerance = 3
    }

    /// Um evento de hook. Os nomes variam: SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop (Claude e Codex);
    /// BeforeAgent, AfterTool, AfterAgent (Gemini)
    func handle(_ info: [String: String], now: Date = Date()) {
        guard let agent = AgentKind(rawValue: info["agent"] ?? ""), let event = info["event"] else { return }
        let e = event.lowercased().replacingOccurrences(of: "_", with: "")
        let sid = info["session"].map { "\(agent.rawValue).\($0)" } ?? "\(agent.rawValue).pid.\(info["pid"] ?? "?")"
        if e == "sessionend" {
            sessions.removeAll { $0.id == sid }
            NotchCenter.shared.update()
            return
        }
        var s = sessions.first { $0.id == sid } ?? AgentSession(id: sid, agent: agent, cwd: info["cwd"], state: .idle, since: now, updated: now)
        let before = s.state
        s.updated = now
        if let c = info["cwd"] { s.cwd = c }
        if let b = info["app"] { s.appBundle = b }
        if let p = info["appPID"].flatMap({ pid_t($0) }) { s.appPID = p }
        if let p = info["pid"].flatMap({ pid_t($0) }) { s.pid = p }

        switch e {
        case "sessionstart":
            if s.state != .working { s.state = .idle }
        case "userpromptsubmit", "beforeagent":
            s.state = .working
            s.turnStart = now
            s.message = nil
            s.step = nil
            if let p = info["prompt"], !p.isEmpty { s.task = p }
        case "pretooluse", "posttooluse", "beforetool", "aftertool", "subagentstart", "subagentstop":
            if s.state != .working { s.state = .working; if s.turnStart == nil { s.turnStart = now } }
            s.message = nil
            if let st = info["step"] { s.step = st }
        case "notification", "permissionrequest":
            // "Esperando sua resposta" depois de um tempo parado não é um pedido novo
            if info["kind"] == "idle_prompt" || (s.state == .done && e == "notification") { break }
            s.state = .waiting
            s.message = info["message"]
        case "stop", "afteragent":
            s.state = .done
        default:
            break
        }
        if let i = sessions.firstIndex(where: { $0.id == sid }) { sessions[i] = s } else { sessions.append(s) }
        if s.state != before { announce(s, from: before, now: now) }
        NotchCenter.shared.update()
    }

    private func announce(_ s: AgentSession, from: AgentSession.State, now: Date) {
        let text: String
        switch s.state {
        case .waiting:
            text = L("%@ espera você · %@", s.agent.short, s.project)
        case .done:
            guard let t = s.turnStart, now.timeIntervalSince(t) >= Self.doneAfter else { return }
            text = L("%@ terminou · %@", s.agent.short, s.project)
        default:
            return
        }
        // Você já está olhando o terminal do agente: não precisa de aviso
        if let b = s.appBundle, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == b { return }
        let shown = NotchCenter.shared.show(icon: s.state == .waiting ? "hand.raised.fill" : "checkmark.circle.fill",
                                            color: s.state == .waiting ? .orange : .green, text: text, duration: 6)
        if UserDefaults.standard.object(forKey: Self.notifyKey) as? Bool ?? true {
            Alerts.shared.notify(id: "menew.agent.\(s.id).\(s.state.rawValue)", title: text, body: s.message ?? (s.state == .waiting ? L("Uma permissão ou pergunta no terminal") : ""))
        } else if !shown {
            HUD.show(icon: "sparkles", color: s.agent.color, text: text, duration: 3)
        }
    }

    /// Traz para a frente o terminal onde o agente está
    func focus(_ s: AgentSession) {
        let app = s.appPID.flatMap { NSRunningApplication(processIdentifier: $0) }
            ?? s.appBundle.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            ?? s.pid.flatMap { pid in
                ProcessTree.ancestors(of: pid).lazy.compactMap { NSRunningApplication(processIdentifier: $0) }.first { $0.activationPolicy == .regular }
            }
        app?.activate()
    }

    /// Sessões cujo processo acabou saem; as que terminaram há muito tempo também
    func prune(now: Date = Date()) {
        guard !demo else { return }
        sessions.removeAll { s in
            if let p = s.pid, !ProcessTree.isAlive(p) { return true }
            return s.pid == nil && now.timeIntervalSince(s.updated) > 3600 * 6
        }
        if isVisible { scanProcesses() }
        NotchCenter.shared.update()
    }

    func scanProcesses() {
        guard !demo else { return }
        Task.detached {
            let found = AgentProcesses.list()
            await MainActor.run { AgentHub.shared.processes = found }
        }
    }

    func showDemo() {
        demo = true
        let now = Date()
        sessions = [
            AgentSession(id: "1", agent: .claude, cwd: "/Users/ana/apps/menew", state: .waiting, since: now.addingTimeInterval(-1800), turnStart: now.addingTimeInterval(-240),
                         message: "Claude needs your permission to use Bash", task: "Add a hover panel to the notch", step: "Bash · swift test",
                         updated: now.addingTimeInterval(-30)),
            AgentSession(id: "2", agent: .codex, cwd: "/Users/ana/apps/api", state: .working, since: now.addingTimeInterval(-900), turnStart: now.addingTimeInterval(-420),
                         task: "Fix the login timeout", step: "Edit · session.ts", updated: now.addingTimeInterval(-5)),
            AgentSession(id: "3", agent: .claude, cwd: "/Users/ana/apps/site", state: .done, since: now.addingTimeInterval(-5400), turnStart: now.addingTimeInterval(-700),
                         updated: now.addingTimeInterval(-120)),
        ]
    }
}

// MARK: Instalar os hooks

/// Põe (e tira) o comando do Menew na configuração de hooks de cada CLI. Mostra o que muda antes, guarda uma cópia
/// do arquivo original (`.menew-backup`) e mexe só nas entradas do Menew.
enum AgentHooks {
    enum Status: Equatable { case notInstalled, installed, outdated }

    static func configURL(_ a: AgentKind) -> URL {
        switch a {
        case .claude: a.home.appendingPathComponent("settings.json")
        case .codex: a.home.appendingPathComponent("hooks.json")
        case .gemini: a.home.appendingPathComponent("settings.json")
        }
    }

    /// Só o que o Menew precisa: começo e fim de cada pedido, antes e depois de cada ferramenta (o passo de agora, e
    /// saber que voltou a trabalhar depois de uma permissão) e os pedidos de atenção
    static func events(_ a: AgentKind) -> [String] {
        switch a {
        case .claude: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]
        case .codex: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
        case .gemini: ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"]
        }
    }

    static var executable: String { Bundle.main.executablePath ?? "/Applications/Menew.app/Contents/MacOS/Menew" }

    static func command(_ a: AgentKind) -> String { "\"\(executable)\" \(AgentHookCommand.flag) \(a.rawValue)" }

    private static func isOurs(_ cmd: String) -> Bool { cmd.contains(" \(AgentHookCommand.flag) ") }

    static func load(_ a: AgentKind) -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL(a)) else { return [:] }
        // Arquivo que não é JSON (com comentários, por exemplo): não mexe
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func status(_ a: AgentKind) -> Status {
        guard let hooks = load(a)?["hooks"] as? [String: Any] else { return .notInstalled }
        let cmds = hooks.values.compactMap { $0 as? [[String: Any]] }.flatMap { $0 }
            .compactMap { $0["hooks"] as? [[String: Any]] }.flatMap { $0 }.compactMap { $0["command"] as? String }.filter(isOurs)
        if cmds.isEmpty { return .notInstalled }
        return cmds.allSatisfy { $0 == command(a) } && events(a).count <= cmds.count ? .installed : .outdated
    }

    /// O arquivo como fica depois (para mostrar antes de gravar)
    static func updated(_ config: [String: Any], agent a: AgentKind, install: Bool) -> [String: Any] {
        var config = config
        var hooks = config["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned = groups.compactMap { g -> [String: Any]? in
                guard let inner = g["hooks"] as? [[String: Any]] else { return g }
                let kept = inner.filter { !isOurs($0["command"] as? String ?? "") }
                if kept.isEmpty { return nil }
                var g = g
                g["hooks"] = kept
                return g
            }
            hooks[event] = cleaned.isEmpty ? nil : cleaned
        }
        if install {
            for event in events(a) {
                var entry: [String: Any] = ["type": "command", "command": command(a)]
                var group: [String: Any] = [:]
                switch a {
                case .claude: entry["timeout"] = 5
                case .codex: break
                case .gemini: entry["timeout"] = 5000; group["matcher"] = "*"
                }
                group["hooks"] = [entry]
                hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
            }
        }
        config["hooks"] = hooks.isEmpty ? nil : hooks
        return config
    }

    enum Failure: Error { case unreadable, write }

    static func apply(_ a: AgentKind, install: Bool) throws {
        guard let current = load(a) else { throw Failure.unreadable }
        let url = configURL(a)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = url.appendingPathExtension("menew-backup")
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: url, to: backup) }
        let next = updated(current, agent: a, install: install)
        guard let data = try? JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]) else { throw Failure.write }
        do { try data.write(to: url, options: .atomic) } catch { throw Failure.write }
    }
}
