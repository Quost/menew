import AppKit
import CryptoKit
import Darwin
import SwiftUI

/// Central de agentes: quais agentes de IA (Claude Code, Codex, Gemini, Cursor, Copilot, Kiro…) estão rodando, quais estão trabalhando, quais terminaram e
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
        // O Copilot e o Kiro passam o evento no comando (`--agent-hook copilot agentStop`)
        let args = CommandLine.arguments
        let argEvent = args.firstIndex(of: flag).flatMap { args.count > $0 + 2 ? args[$0 + 2] : nil }
        info["event"] = obj["hook_event_name"] as? String ?? obj["hookEventName"] as? String ?? argEvent ?? args.last
        // Cada ferramenta chama a sessão de um jeito: session_id, sessionId (Copilot), conversation_id (Cursor)
        info["session"] = ["session_id", "sessionId", "conversation_id"].lazy.compactMap { obj[$0] as? String }.first
        info["cwd"] = obj["cwd"] as? String ?? (obj["workspace_roots"] as? [String])?.first ?? FileManager.default.currentDirectoryPath
        info["message"] = (obj["message"] as? String).map { String($0.prefix(200)) }
        info["kind"] = obj["notification_type"] as? String ?? obj["notificationType"] as? String
        if let (tool, detail) = step(obj) {
            info["tool"] = tool
            info["detail"] = detail
        }
        // O Kiro CLI passa o pedido numa variável de ambiente
        let prompt = obj["prompt"] as? String ?? ProcessInfo.processInfo.environment["USER_PROMPT"]
        info["prompt"] = prompt.flatMap(AgentStep.task)
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
        // O Cursor lê a resposta em JSON (no envio do pedido, se pode seguir); os outros, nada
        if agent == AgentKind.cursor.rawValue {
            print(info["event"]?.lowercased() == "beforesubmitprompt" ? #"{"continue":true}"# : "{}")
        }
        exit(0)
    }
}

extension AgentHookCommand {
    /// A ferramenta e o detalhe que importa: o arquivo, a descrição do comando, o comando, a busca
    static func step(_ obj: [String: Any]) -> (tool: String, detail: String?)? {
        // O Cursor manda o comando e o arquivo direto, em eventos próprios
        if obj["tool_name"] == nil, obj["toolName"] == nil {
            if let c = obj["command"] as? String, !c.isEmpty { return ("Bash", oneLine(c, 160)) }
            if let f = obj["file_path"] as? String, !f.isEmpty { return ("Edit", URL(fileURLWithPath: f).lastPathComponent) }
        }
        guard let tool = obj["tool_name"] as? String ?? obj["toolName"] as? String, !tool.isEmpty else { return nil }
        // O Copilot manda os argumentos como texto JSON
        let input = AgentFiles.dict(obj["tool_input"] ?? obj["toolArgs"])
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
    /// O nome do processo do agente, ao subir a árvore de processos a partir do hook
    static func matches(_ name: String, agent: String) -> Bool {
        let n = name.lowercased()
        switch agent {
        case "claude": return n == "claude"
        case "codex": return n == "codex" || n.hasPrefix("codex-")
        // Os feitos em Node aparecem como "node"
        case "gemini", "qwen", "copilot", "amp", "openclaw": return n == agent || n == "node"
        case "cursor": return n == "cursor-agent" || n == "node" || n.hasPrefix("cursor")
        case "kiro": return n.hasPrefix("kiro")
        case "opencode", "droid", "kimi", "goose": return n == agent || n.hasPrefix(agent + "-")
        case "pi": return n == "pi" || n == "node" || n == "bun"
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
            // Servidores e serviços de fundo não são uma sessão sua (opencode serve, gateway do OpenClaw, goosed)
            if rest.contains(where: { ["serve", "server", "gateway", "daemon", "acp"].contains($0) }) { return nil }
            switch exe {
            case "claude": return (.claude, pid)
            case "codex": return (.codex, pid)
            case "gemini": return (.gemini, pid)
            case "opencode": return (.opencode, pid)
            case "cursor-agent": return (.cursor, pid)
            case "copilot": return (.copilot, pid)
            case "kiro-cli", "kiro-cli-chat": return (.kiro, pid)
            case "droid": return (.droid, pid)
            case "qwen": return (.qwen, pid)
            case "amp": return (.amp, pid)
            case "openclaw": return (.openclaw, pid)
            case "kimi": return (.kimi, pid)
            case "goose": return (.goose, pid)
            case "pi": return (.pi, pid)
            case "node", "bun":
                // node /opt/homebrew/bin/gemini …, node …/@github/copilot/index.js …
                guard let script = rest.first?.lowercased() else { return nil }
                let scripts: [(AgentKind, [String])] = [
                    (.gemini, ["/gemini", "gemini-cli/dist/index.js"]),
                    (.copilot, ["/copilot", "@github/copilot/"]),
                    (.qwen, ["/qwen", "qwen-code/"]),
                    (.amp, ["/amp", "@sourcegraph/amp/"]),
                    (.cursor, ["/cursor-agent", "cursor-agent/"]),
                    (.openclaw, ["/openclaw", "openclaw/"]),
                    (.opencode, ["/opencode", "opencode-ai/"]),
                    (.pi, ["/pi", "pi-coding-agent/"]),
                ]
                return scripts.first { _, marks in marks.contains { script.hasSuffix($0) || ($0.hasSuffix("/") && script.contains($0)) } }.map { ($0.0, pid) }
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
        // Das que não têm hooks, o uso gravado há pouco naquela pasta diz que está trabalhando
        let recent = AgentUsageStore.shared.records.filter { $0.date > Date().addingTimeInterval(-180) }
        let extra = processes.filter { !known.contains($0.pid) && AgentHooks.status($0.agent) != .installed }.map { p in
            let busy = recent.contains { $0.agent == p.agent && ($0.project == AgentDates.project(p.cwd) || p.cwd == nil) }
            return AgentSession(id: "pid.\(p.pid)", agent: p.agent, cwd: p.cwd, state: busy ? .working : .running, since: Date(), pid: p.pid,
                                updated: Date(), fromHooks: false)
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
        // Pi, OpenCode e Amp avisam por um arquivo que o plugin do Menew escreve
        AgentEventFiles.shared.start()
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
        case "sessionstart", "agentspawn":
            if s.state != .working { s.state = .idle }
        case "userpromptsubmit", "beforeagent", "beforesubmitprompt", "userpromptsubmitted":
            s.state = .working
            s.turnStart = now
            s.message = nil
            s.tool = nil
            s.detail = nil
            if let p = info["prompt"].flatMap(AgentStep.task) { s.task = p }
        case "pretooluse", "posttooluse", "beforetool", "aftertool", "subagentstart", "subagentstop",
             "aftershellexecution", "afterfileedit", "posttoolusefailure":
            if s.state != .working { s.state = .working; if s.turnStart == nil { s.turnStart = now } }
            s.message = nil
            if let t = info["tool"] { s.tool = t; s.detail = info["detail"] }
        case "notification", "permissionrequest":
            // "Esperando sua resposta" depois de um tempo parado não é um pedido novo
            if ["idle_prompt", "agent_idle", "agent_complete"].contains(info["kind"] ?? "") || (s.state == .done && e == "notification") { break }
            s.state = .waiting
            s.message = info["message"]
            if let t = info["tool"] { s.tool = t; s.detail = info["detail"] }
        case "stop", "afteragent", "agentstop":
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
            AgentSession(id: "4", agent: .cursor, cwd: "/Users/ana/apps/mobile", state: .working, since: now.addingTimeInterval(-600), turnStart: now.addingTimeInterval(-90),
                         task: "Add dark mode to settings", tool: "Bash", detail: "npm test", updated: now.addingTimeInterval(-8)),
        ]
    }
}

// MARK: Instalar os hooks

/// Põe (e tira) o comando do Menew na configuração de hooks de cada CLI. Mostra o que muda antes, guarda uma cópia
/// do arquivo original (`.menew-backup`) e mexe só nas entradas do Menew.
enum AgentHooks {
    enum Status: Equatable { case notInstalled, installed, outdated }

    /// Como cada ferramenta guarda os hooks
    enum Style {
        /// `{"hooks": {"Evento": [{"matcher": …, "hooks": [{"type": "command", "command": …}]}]}}` (Claude, Codex, Gemini, Droid, Qwen)
        case groups
        /// O mesmo, mas o arquivo inteiro é o `hooks` (o `~/.factory/hooks.json` do Droid)
        case rootGroups
        /// `{"version": 1, "hooks": {"evento": [{"command": …}]}}` (Cursor)
        case flat
        /// Um arquivo só do Menew numa pasta de hooks, que ele cria e apaga inteiro (Copilot CLI e Kiro CLI)
        case ownFile
    }

    static func style(_ a: AgentKind) -> Style {
        switch a {
        case .cursor: .flat
        case .copilot, .kiro: .ownFile
        case .droid: FileManager.default.fileExists(atPath: droidHooksFile.path) ? .rootGroups : .groups
        default: .groups
        }
    }

    private static var droidHooksFile: URL { AgentFiles.home.appendingPathComponent(".factory/hooks.json") }

    static func configURL(_ a: AgentKind) -> URL {
        let h = AgentFiles.home
        switch a {
        case .claude: return h.appendingPathComponent(".claude/settings.json")
        case .codex: return h.appendingPathComponent(".codex/hooks.json")
        case .gemini: return h.appendingPathComponent(".gemini/settings.json")
        case .cursor: return h.appendingPathComponent(".cursor/hooks.json")
        case .copilot: return h.appendingPathComponent(".copilot/hooks/menew.json")
        case .kiro: return h.appendingPathComponent(".kiro/hooks/menew.json")
        case .droid: return style(a) == .rootGroups ? droidHooksFile : h.appendingPathComponent(".factory/settings.json")
        case .qwen: return h.appendingPathComponent(".qwen/settings.json")
        case .pi, .opencode, .amp: return AgentPlugins.targets(a).first ?? a.home
        default: return a.home
        }
    }

    /// Só o que o Menew precisa: começo e fim de cada pedido, antes e depois de cada ferramenta (o passo de agora, e
    /// saber que voltou a trabalhar depois de uma permissão) e os pedidos de atenção. No Cursor e no Copilot, só eventos
    /// que não decidem nada (um hook "antes" de ferramenta precisa responder se deixa rodar).
    static func events(_ a: AgentKind) -> [String] {
        switch a {
        case .claude, .droid: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]
        case .codex: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
        case .gemini: ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"]
        case .qwen: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "PermissionRequest", "Stop", "SessionEnd"]
        case .cursor: ["sessionStart", "beforeSubmitPrompt", "postToolUse", "afterShellExecution", "afterFileEdit", "stop", "sessionEnd"]
        case .copilot: ["sessionStart", "userPromptSubmitted", "postToolUse", "notification", "agentStop", "sessionEnd"]
        case .kiro: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]
        default: []
        }
    }

    static var executable: String { Bundle.main.executablePath ?? "/Applications/Menew.app/Contents/MacOS/Menew" }

    static func command(_ a: AgentKind) -> String { "\"\(executable)\" \(AgentHookCommand.flag) \(a.rawValue)" }

    /// O Copilot e o Kiro não dizem o nome do evento na entrada: vai junto no comando
    static func command(_ a: AgentKind, event: String) -> String {
        [.copilot, .kiro, .cursor].contains(a) ? command(a) + " " + event : command(a)
    }

    private static func isOurs(_ cmd: String) -> Bool { cmd.contains(" \(AgentHookCommand.flag) ") }

    static func load(_ a: AgentKind) -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL(a)) else { return [:] }
        // Arquivo que não é JSON (com comentários, por exemplo): não mexe
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Todos os comandos do Menew no arquivo, onde quer que estejam
    static func ourCommands(_ obj: Any) -> [String] {
        if let d = obj as? [String: Any] {
            return d.flatMap { k, v -> [String] in
                if ["command", "bash"].contains(k), let c = v as? String { return isOurs(c) ? [c] : [] }
                return ourCommands(v)
            }
        }
        if let l = obj as? [Any] { return l.flatMap(ourCommands) }
        return []
    }

    static func status(_ a: AgentKind) -> Status {
        if AgentPlugins.supports(a) { return AgentPlugins.status(a) }
        guard a.hasHooks, let config = load(a) else { return .notInstalled }
        let cmds = ourCommands(config)
        if cmds.isEmpty { return .notInstalled }
        let wanted = Set(events(a).map { command(a, event: $0) })
        let current = Set(cmds) == wanted || (Set(cmds).isSuperset(of: wanted) && cmds.allSatisfy { $0.hasPrefix(command(a)) })
        // O Codex (também o de dentro do app ChatGPT) ignora em silêncio os hooks sem aprovação no config.toml
        if a == .codex, current, !CodexHookTrust.isTrusted(CodexHookTrust.entries(config, hooksFile: configURL(a)), in: CodexHookTrust.configText()) {
            return .outdated
        }
        return current ? .installed : .outdated
    }

    /// O arquivo como fica depois (para mostrar antes de gravar)
    static func updated(_ config: [String: Any], agent a: AgentKind, install: Bool) -> [String: Any] {
        switch style(a) {
        case .ownFile:
            guard install else { return [:] }
            if a == .kiro {
                return ["version": "v1", "hooks": events(a).map { e -> [String: Any] in
                    ["name": "menew-\(e)", "trigger": e, "action": ["type": "command", "command": command(a, event: e)], "timeout": 5, "enabled": true]
                }]
            }
            var hooks: [String: Any] = [:]
            for e in events(a) { hooks[e] = [["type": "command", "bash": command(a, event: e), "timeoutSec": 5]] }
            return ["version": 1, "hooks": hooks]
        case .flat:
            var config = config
            var hooks = config["hooks"] as? [String: Any] ?? [:]
            for (event, value) in hooks {
                guard let list = value as? [[String: Any]] else { continue }
                let kept = list.filter { !isOurs($0["command"] as? String ?? "") }
                hooks[event] = kept.isEmpty ? nil : kept
            }
            if install {
                for e in events(a) { hooks[e] = (hooks[e] as? [[String: Any]] ?? []) + [["command": command(a, event: e), "timeout": 5]] }
                if config["version"] == nil { config["version"] = 1 }
            }
            config["hooks"] = hooks.isEmpty ? nil : hooks
            return config
        case .groups, .rootGroups:
            let root = style(a) == .rootGroups
            var config = config
            var hooks = root ? config : config["hooks"] as? [String: Any] ?? [:]
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
                    var entry: [String: Any] = ["type": "command", "command": command(a, event: event)]
                    var group: [String: Any] = [:]
                    switch a {
                    case .codex: break
                    case .gemini: entry["timeout"] = 5000; group["matcher"] = "*"
                    case .qwen: entry["timeout"] = 5; group["matcher"] = "*"
                    default: entry["timeout"] = 5
                    }
                    group["hooks"] = [entry]
                    hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
                }
            }
            if root { return hooks }
            config["hooks"] = hooks.isEmpty ? nil : hooks
            return config
        }
    }

    enum Failure: Error { case unreadable, write }

    static func apply(_ a: AgentKind, install: Bool) throws {
        // Modo demo: não mexe nos arquivos de configuração dos agentes
        guard !DemoMode.isOn else { throw Failure.write }
        if AgentPlugins.supports(a) { return try AgentPlugins.apply(a, install: install) }
        guard let current = load(a) else { throw Failure.unreadable }
        let url = configURL(a)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = url.appendingPathExtension("menew-backup")
        if style(a) != .ownFile, fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: url, to: backup) }
        let next = updated(current, agent: a, install: install)
        // O arquivo só do Menew sai inteiro ao desligar
        if style(a) == .ownFile, !install {
            try? fm.removeItem(at: url)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]) else { throw Failure.write }
        do { try data.write(to: url, options: .atomic) } catch { throw Failure.write }
        if a == .codex { try CodexHookTrust.write(CodexHookTrust.entries(next, hooksFile: url)) }
    }
}

/// O Codex só roda um hook do hooks.json se o config.toml tiver a aprovação dele: `[hooks.state."<arquivo>:<evento>:<grupo>:<hook>"]`
/// com `trusted_hash`. O terminal pergunta ao abrir; o app ChatGPT (que roda o Codex por dentro) só pula o hook, sem avisar.
/// Ligar os avisos já é a sua aprovação, então o Menew grava a dos comandos dele num bloco próprio do config.toml.
enum CodexHookTrust {
    struct Entry: Equatable { let key: String; let hash: String }

    static let begin = "# >>> menew hooks"
    static let end = "# <<< menew hooks"
    static var configURL: URL { AgentFiles.home.appendingPathComponent(".codex/config.toml") }

    static func configText() -> String { (try? String(contentsOf: configURL, encoding: .utf8)) ?? "" }

    /// "UserPromptSubmit" → "user_prompt_submit", como o Codex chama o evento na chave
    static func eventKey(_ event: String) -> String {
        event.reduce(into: "") { out, c in
            if c.isUppercase, !out.isEmpty { out += "_" }
            out += c.lowercased()
        }
    }

    /// O hash que o Codex calcula: SHA-256 do JSON compacto, com chaves em ordem, do evento e do hook normalizado
    /// (timeout padrão de 600 s; 1 s no SessionEnd). Sem matcher, ele não entra.
    static func hash(event: String, handler: [String: Any]) -> String? {
        guard let command = handler["command"] as? String else { return nil }
        let key = eventKey(event)
        var h: [String: Any] = ["type": "command", "command": command,
                                "timeout": handler["timeout"] as? Int ?? (key == "session_end" ? 1 : 600),
                                "async": handler["async"] as? Bool ?? false]
        if let s = handler["statusMessage"] as? String { h["statusMessage"] = s }
        let identity: [String: Any] = ["event_name": key, "hooks": [h]]
        guard let data = try? JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// As aprovações dos comandos do Menew no hooks.json, pela posição de cada um (o Codex aprova por posição)
    static func entries(_ hooksConfig: [String: Any], hooksFile: URL) -> [Entry] {
        let hooks = hooksConfig["hooks"] as? [String: Any] ?? [:]
        return hooks.keys.sorted().flatMap { event -> [Entry] in
            let groups = hooks[event] as? [[String: Any]] ?? []
            return groups.enumerated().flatMap { gi, group -> [Entry] in
                guard group["matcher"] == nil else { return [] }
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                return handlers.enumerated().compactMap { hi, handler in
                    guard let cmd = handler["command"] as? String, cmd.contains(" \(AgentHookCommand.flag) "),
                          let hash = hash(event: event, handler: handler) else { return nil }
                    return Entry(key: "\(hooksFile.path):\(eventKey(event)):\(gi):\(hi)", hash: hash)
                }
            }
        }
    }

    static func header(_ key: String) -> String {
        "[hooks.state.\"" + key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"]"
    }

    /// Cada aprovação está no arquivo (no bloco do Menew ou gravada pelo próprio Codex), com o hash certo e ligada
    static func isTrusted(_ entries: [Entry], in toml: String) -> Bool {
        entries.allSatisfy { e in
            guard let r = toml.range(of: header(e.key)) else { return false }
            let rest = toml[r.upperBound...]
            let table = rest.range(of: "\n[").map { rest[..<$0.lowerBound] } ?? rest
            return table.contains("trusted_hash = \"\(e.hash)\"") && !table.contains("enabled = false")
        }
    }

    /// O config.toml sem o bloco antigo do Menew e com o novo no fim. Uma chave que o Codex já gravou fora do bloco
    /// fica como está: repetir a tabela quebraria o arquivo.
    static func updated(_ toml: String, entries: [Entry]) -> String {
        var text = toml
        if let b = text.range(of: begin), let e = text.range(of: end, range: b.upperBound..<text.endIndex) {
            var upper = e.upperBound
            if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
            text.removeSubrange(b.lowerBound..<upper)
            // A linha em branco que separava o bloco
            if b.lowerBound == text.endIndex { while text.hasSuffix("\n\n") { text.removeLast() } }
        }
        let fresh = entries.filter { !text.contains(header($0.key)) }
        guard !fresh.isEmpty else { return text }
        while text.hasSuffix("\n\n") { text.removeLast() }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        var block = (text.isEmpty ? "" : "\n") + begin + "\n# Aprovação dos hooks do Menew (Menew --agent-hook codex). O Menew regrava este bloco.\n"
        for e in fresh { block += "\n\(header(e.key))\nenabled = true\ntrusted_hash = \"\(e.hash)\"\n" }
        return text + block + end + "\n"
    }

    static func write(_ entries: [Entry]) throws {
        let current = configText()
        let next = updated(current, entries: entries)
        guard next != current else { return }
        let fm = FileManager.default
        let backup = configURL.appendingPathExtension("menew-backup")
        if fm.fileExists(atPath: configURL.path), !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: configURL, to: backup) }
        try? fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try next.write(to: configURL, atomically: true, encoding: .utf8) } catch { throw AgentHooks.Failure.write }
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
