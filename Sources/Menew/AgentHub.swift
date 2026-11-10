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
        if let (tool, detail) = step(obj) {
            info["tool"] = tool
            info["detail"] = detail
        }
        info["prompt"] = (obj["prompt"] as? String).flatMap(AgentStep.task)
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
    /// A ferramenta e o detalhe que importa: o arquivo, a descrição do comando, o comando, a busca
    static func step(_ obj: [String: Any]) -> (tool: String, detail: String?)? {
        guard let tool = obj["tool_name"] as? String, !tool.isEmpty else { return nil }
        let input = obj["tool_input"] as? [String: Any] ?? [:]
        var detail: String?
        if let f = (input["file_path"] ?? input["path"] ?? input["notebook_path"] ?? input["absolute_path"]) as? String, !f.isEmpty {
            detail = URL(fileURLWithPath: f).lastPathComponent
        } else {
            detail = ["description", "command", "cmd", "pattern", "url", "query", "prompt"].lazy
                .compactMap { input[$0] as? String }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            // O Codex passa o comando como lista: ["bash", "-lc", "swift test"]
            if detail == nil, let parts = input["command"] as? [String] { detail = parts.last }
        }
        return (tool, detail.map { oneLine($0, 160) })
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
    /// O que você pediu (a primeira linha do prompt) e o passo de agora (a ferramenta e o detalhe)
    var task: String?
    var tool: String?
    var detail: String?
    /// Quanto levou o último pedido (para o aviso de pronto)
    var lastDuration: TimeInterval?
    var appBundle: String?
    var appPID: pid_t?
    var pid: pid_t?
    var updated: Date
    /// Veio dos hooks (sabe o estado) ou só da lista de processos (sabe que está rodando)
    var fromHooks = true

    var project: String { AgentDates.project(cwd) }

    /// "Editando AgentsView.swift", "Rodando swift test"
    var step: String? { AgentStep.text(tool: tool, detail: detail) }
    var stepIcon: String { AgentStep.kind(tool ?? "").icon }

    /// O que dizer quando espera você: o pedido de permissão com o passo, ou que espera uma resposta
    var waitingText: String {
        let m = (message ?? "").lowercased()
        if m.contains("permission") || m.contains("approv") || m.contains("permiss") {
            return step.map { L("Pede permissão: %@", $0) } ?? L("Pede sua permissão")
        }
        if m.isEmpty || m.contains("waiting for your input") || m.contains("waiting for input") { return L("Espera sua resposta") }
        return message ?? L("Espera sua resposta")
    }
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
            s.tool = nil
            s.detail = nil
            if let p = info["prompt"].flatMap(AgentStep.task) { s.task = p }
        case "pretooluse", "posttooluse", "beforetool", "aftertool", "subagentstart", "subagentstop":
            if s.state != .working { s.state = .working; if s.turnStart == nil { s.turnStart = now } }
            s.message = nil
            if let t = info["tool"] { s.tool = t; s.detail = info["detail"] }
        case "notification", "permissionrequest":
            // "Esperando sua resposta" depois de um tempo parado não é um pedido novo
            if info["kind"] == "idle_prompt" || (s.state == .done && e == "notification") { break }
            s.state = .waiting
            s.message = info["message"]
            if let t = info["tool"] { s.tool = t; s.detail = info["detail"] }
        case "stop", "afteragent":
            s.state = .done
            s.lastDuration = s.turnStart.map { now.timeIntervalSince($0) }
        default:
            break
        }
        if let i = sessions.firstIndex(where: { $0.id == sid }) { sessions[i] = s } else { sessions.append(s) }
        if s.state != before { announce(s, from: before, now: now) }
        NotchCenter.shared.update()
    }

    private func announce(_ s: AgentSession, from: AgentSession.State, now: Date) {
        let waiting = s.state == .waiting
        guard waiting || s.state == .done else { return }
        if !waiting { guard let d = s.lastDuration, d >= Self.doneAfter else { return } }
        // Você já está olhando o terminal do agente: não precisa de aviso
        if let b = s.appBundle, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == b { return }
        let line = waiting ? s.waitingText : (s.task ?? s.step ?? s.agent.name)
        let shown = NotchCenter.shared.showAgent(.agentEvent(id: s.id, agent: s.agent, project: s.project, waiting: waiting, line: line,
                                                              duration: waiting ? nil : s.lastDuration), duration: waiting ? 12 : 7)
        guard UserDefaults.standard.object(forKey: Self.notifyKey) as? Bool ?? true else {
            if !shown { HUD.show(icon: waiting ? "hand.raised.fill" : "checkmark.circle.fill", color: waiting ? .orange : .green,
                                 text: "\(s.agent.short) · \(s.project)", duration: 3) }
            return
        }
        let title = waiting ? L("%@ precisa de você · %@", s.agent.short, s.project) : L("%@ terminou · %@", s.agent.short, s.project)
        var body = line
        if !waiting, let d = s.lastDuration { body += " · " + L("levou %@", AgentStep.duration(d)) }
        Alerts.shared.notify(id: "menew.agent.\(s.id).\(s.state.rawValue)", title: title, body: body, userInfo: ["agentSession": s.id])
    }

    func focus(id: String) {
        if let s = sessions.first(where: { $0.id == id }) { focus(s) }
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
                         message: "Claude needs your permission to use Bash", task: "Add a hover panel to the notch", tool: "Bash", detail: "swift test",
                         updated: now.addingTimeInterval(-30)),
            AgentSession(id: "2", agent: .codex, cwd: "/Users/ana/apps/api", state: .working, since: now.addingTimeInterval(-900), turnStart: now.addingTimeInterval(-420),
                         task: "Fix the login timeout", tool: "Edit", detail: "session.ts", updated: now.addingTimeInterval(-5)),
            AgentSession(id: "3", agent: .claude, cwd: "/Users/ana/apps/site", state: .done, since: now.addingTimeInterval(-5400), turnStart: now.addingTimeInterval(-700),
                         task: "Update the pricing page", lastDuration: 252, updated: now.addingTimeInterval(-120)),
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

/// Como mostrar um passo: um ícone, um verbo e o detalhe limpo ("cd /tmp/x && swift test" → "swift test")
enum AgentStep {
    static func kind(_ tool: String) -> (icon: String, verb: String?) {
        let t = tool.lowercased()
        if t.hasPrefix("mcp__") { return ("puzzlepiece.extension", nil) }
        switch t {
        case "bash", "shell", "exec_command", "run_shell_command", "local_shell", "unified_exec", "bashoutput":
            return ("terminal", L("Rodando"))
        case "edit", "multiedit", "apply_patch", "replace", "edit_file", "notebookedit":
            return ("pencil", L("Editando"))
        case "write", "write_file", "create_file":
            return ("doc.badge.plus", L("Criando"))
        case "read", "read_file", "read_many_files", "view_image", "view":
            return ("doc.text", L("Lendo"))
        case "grep", "glob", "ls", "search_file_content", "list_directory", "file_search", "find":
            return ("magnifyingglass", L("Buscando"))
        case "webfetch", "websearch", "web_fetch", "google_web_search", "web_search":
            return ("globe", L("Na web"))
        case "task", "agent", "spawn_agent":
            return ("person.2", L("Subagente"))
        case "todowrite", "update_plan", "write_todos":
            return ("checklist", L("Planejando"))
        default:
            return ("wrench.and.screwdriver", nil)
        }
    }

    static func text(tool: String?, detail: String?) -> String? {
        guard let tool, !tool.isEmpty else { return detail }
        let k = kind(tool)
        // mcp__menew__search_notes → "menew: search_notes"
        let name = tool.hasPrefix("mcp__") ? tool.dropFirst(5).replacingOccurrences(of: "__", with: ": ") : tool
        let d = detail.map { k.icon == "terminal" ? clean($0) : $0 }.flatMap { $0.isEmpty ? nil : $0 }
        switch (k.verb, d) {
        case let (verb?, d?): return "\(verb) \(d)"
        case let (verb?, nil): return verb
        case let (nil, d?): return "\(name) · \(d)"
        default: return name
        }
    }

    /// Tira o que só atrapalha de ler um comando: `cd pasta &&`, variáveis no começo, o caminho do executável
    static func clean(_ command: String) -> String {
        var parts = command.components(separatedBy: " && ").map { $0.trimmingCharacters(in: .whitespaces) }
        while parts.count > 1, let f = parts.first, f.hasPrefix("cd ") || f.hasPrefix("export ") || f.hasPrefix("source ") { parts.removeFirst() }
        var words = parts.joined(separator: " && ").split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while let w = words.first, w.contains("="), !w.hasPrefix("-"), words.count > 1 { words.removeFirst() }
        if let w = words.first, w.contains("/"), !w.hasPrefix(".") { words[0] = String(w.split(separator: "/").last ?? Substring(w)) }
        return words.joined(separator: " ")
    }

    /// O pedido em uma linha, sem as marcas internas que alguns agentes recebem junto
    /// (`<agent-message from="…">`, `<system-reminder>`, `<command-name>`): a primeira linha com texto de verdade
    static func task(_ prompt: String) -> String? {
        let noTags = prompt.replacingOccurrences(of: "<[A-Za-z/!][^>]*>", with: "\n", options: .regularExpression)
        guard let line = noTags.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty })
        else { return nil }
        return line.count > 140 ? String(line.prefix(139)) + "…" : line
    }

    /// 252 → "4 min 12 s"; 40 → "40 s"; 4000 → "1 h 6 min"
    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s" }
        return "\(s / 3600) h \(s / 60 % 60) min"
    }
}
