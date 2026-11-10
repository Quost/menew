import AppKit
import Foundation
import SwiftUI

/// Servidor MCP do Menew: `Menew --mcp`, que Claude Code, Codex, Gemini, Claude Desktop e Cursor abrem como um
/// processo local e com quem conversam pela entrada e saída padrão (JSON-RPC, uma mensagem por linha). Nada de rede.
/// Os agentes podem buscar na memória, nas notas, nas atas e (se você ligar) no clipboard, ver como está o Mac e
/// o uso dos agentes, e pedir ao Menew aberto para guardar algo ou avisar você. Cada fonte tem seu interruptor.
enum MCPSource: String, CaseIterable, Identifiable {
    case memory, notes, recordings, clipboard, system, usage, write
    var id: String { rawValue }
    var key: String { "mcp.\(rawValue)" }
    /// O clipboard vem desligado: pode ter coisas que você copiou sem pensar em mostrar a uma IA
    var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? (self != .clipboard) }

    var title: String {
        switch self {
        case .memory: L("Memória")
        case .notes: L("Notas")
        case .recordings: L("Gravações e atas")
        case .clipboard: L("Histórico do clipboard")
        case .system: L("Como está o Mac")
        case .usage: L("Uso dos agentes")
        case .write: L("Guardar na memória, criar notas e avisar você")
        }
    }

    var detail: String {
        switch self {
        case .memory: L("Buscar no que você guardou com o atalho da memória")
        case .notes: L("Buscar e ler notas (nunca as protegidas ou de senhas)")
        case .recordings: L("Listar reuniões e ler as atas com as tarefas")
        case .clipboard: L("Buscar no que você copiou (nunca senhas)")
        case .system: L("CPU, memória, disco, bateria e os processos que mais gastam")
        case .usage: L("Tokens e limites do Claude Code, Codex e Gemini")
        case .write: L("Só com o Menew aberto; aparece um aviso a cada vez")
        }
    }

    var icon: String {
        switch self {
        case .memory: "brain.head.profile"
        case .notes: "note.text"
        case .recordings: "waveform"
        case .clipboard: "doc.on.clipboard"
        case .system: "gauge.with.dots.needle.67percent"
        case .usage: "chart.bar.fill"
        case .write: "square.and.pencil"
        }
    }
}

@MainActor
enum MCPServer {
    nonisolated static let flag = "--mcp"
    nonisolated static let bridge = Notification.Name("com.matheusquost.menew.mcp")
    private static let versions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    private static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Menew", isDirectory: true)
    }

    static func run() -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let reply = handle(msg) { send(reply) }
        }
        exit(0)
    }

    private static func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    /// Uma mensagem JSON-RPC; nil para notificações (que não têm resposta)
    static func handle(_ msg: [String: Any]) -> [String: Any]? {
        guard let method = msg["method"] as? String else { return nil }
        guard let id = msg["id"] else { return nil }
        let params = msg["params"] as? [String: Any] ?? [:]
        func ok(_ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return ok([
                "protocolVersion": versions.contains(asked) ? asked : versions[1],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "menew", "title": "Menew", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"],
                "instructions": "Menew is the user's Mac menu bar app. Use it to look up what the user saved (memory, notes, meeting minutes), check the Mac's health, see AI agent usage limits, or save something for the user and notify them.",
            ])
        case "ping":
            return ok([:])
        case "tools/list":
            return ok(["tools": tools.filter { $0.source.isOn }.map(\.definition)])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard let tool = tools.first(where: { $0.name == name }) else {
                return ["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool: \(name)"]]
            }
            guard tool.source.isOn else { return ok(text("This Menew tool is turned off in Menew › AI agents › MCP.", error: true)) }
            return ok(tool.run(args))
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]]
        }
    }

    private static func text(_ s: String, error: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": s]], "isError": error]
    }

    // MARK: Ferramentas

    struct Tool {
        let name: String
        let source: MCPSource
        let description: String
        let properties: [String: Any]
        let required: [String]
        let readOnly: Bool
        let run: ([String: Any]) -> [String: Any]

        var definition: [String: Any] {
            ["name": name, "description": description,
             "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
             "annotations": ["readOnlyHint": readOnly, "openWorldHint": false]]
        }
    }

    private static let queryProp: [String: Any] = ["type": "string", "description": "Words to search for. Empty returns the most recent."]
    private static let limitProp: [String: Any] = ["type": "integer", "description": "Maximum results (default 10, max 50)."]

    private static func limit(_ a: [String: Any]) -> Int { min(50, max(1, (a["limit"] as? NSNumber)?.intValue ?? 10)) }
    private static func query(_ a: [String: Any]) -> String { (a["query"] as? String ?? "").trimmingCharacters(in: .whitespaces) }
    private static func iso(_ d: Date) -> String { d.ISO8601Format() }

    static let tools: [Tool] = [
        Tool(name: "search_memory", source: .memory,
             description: "Search the user's Menew memory: screen captures, texts and links the user chose to save, with the text read from them, their title, summary, tags, app and link.",
             properties: ["query": queryProp, "limit": limitProp], required: [], readOnly: true) { a in
            let items = loadMemory()
            let found = (query(a).isEmpty ? items : MemoryStore.search(items, query(a))).prefix(limit(a))
            if found.isEmpty { return text("Nothing found in memory.") }
            return text(found.map { m in
                var s = "## \(m.title)\nid: \(m.id.uuidString) · \(iso(m.date))"
                if let app = m.app { s += " · \(app)" }
                if let u = m.url { s += "\n\(u)" }
                if !m.summary.isEmpty { s += "\n\(m.summary)" }
                if !m.tags.isEmpty { s += "\ntags: \(m.tags.joined(separator: ", "))" }
                if !m.text.isEmpty { s += "\n\n\(m.text.prefix(2000))" }
                return s
            }.joined(separator: "\n\n---\n\n"))
        },
        Tool(name: "search_notes", source: .notes,
             description: "Search the user's Menew notes (Markdown). Protected and password notes are never returned. Returns the first lines; use read_note for the full text.",
             properties: ["query": queryProp, "limit": limitProp], required: [], readOnly: true) { a in
            let words = PaletteSearch.fold(query(a)).split(separator: " ").map(String.init)
            let notes = loadNotes().filter { n in words.allSatisfy { PaletteSearch.fold(n.text).contains($0) } }.prefix(limit(a))
            if notes.isEmpty { return text("No notes found.") }
            return text(notes.map { "- id: \($0.id.uuidString) · updated \(iso($0.updated))\n  \($0.text.split(separator: "\n").prefix(3).joined(separator: " / ").prefix(240))" }
                .joined(separator: "\n"))
        },
        Tool(name: "read_note", source: .notes, description: "Read one Menew note in full, by the id from search_notes.",
             properties: ["id": ["type": "string"]], required: ["id"], readOnly: true) { a in
            guard let id = (a["id"] as? String).flatMap(UUID.init(uuidString:)), let n = loadNotes().first(where: { $0.id == id }) else {
                return text("Note not found.", error: true)
            }
            return text(n.text)
        },
        Tool(name: "list_recordings", source: .recordings,
             description: "List the user's recorded meetings and voice notes with their title, date and summary, newest first.",
             properties: ["query": queryProp, "limit": limitProp], required: [], readOnly: true) { a in
            let q = PaletteSearch.fold(query(a))
            let recs = loadRecordings().filter { q.isEmpty || $0.haystack.contains(q) }.prefix(limit(a))
            if recs.isEmpty { return text("No recordings found.") }
            return text(recs.map { r in
                "- id: \(r.id.uuidString) · \(iso(r.date)) · \(Int(r.duration / 60)) min\n  \(r.title)\(r.summary.isEmpty ? "" : ": \(r.summary.prefix(300))")"
            }.joined(separator: "\n"))
        },
        Tool(name: "get_recording", source: .recordings,
             description: "Read the minutes of a recording (summary, topics, decisions, tasks with owner and due date). Set transcript to true to also get the transcript.",
             properties: ["id": ["type": "string"], "transcript": ["type": "boolean"]], required: ["id"], readOnly: true) { a in
            guard let id = (a["id"] as? String).flatMap(UUID.init(uuidString:)), let r = loadRecordings().first(where: { $0.id == id }) else {
                return text("Recording not found.", error: true)
            }
            var s = r.markdown
            if a["transcript"] as? Bool == true, !r.transcript.isEmpty { s += "\n\n## Transcript\n\n\(r.transcript)" }
            return text(s)
        },
        Tool(name: "search_clipboard", source: .clipboard,
             description: "Search the text the user copied recently (clipboard history, including text read from copied images). Items from password managers are never stored.",
             properties: ["query": queryProp, "limit": limitProp], required: [], readOnly: true) { a in
            let words = PaletteSearch.fold(query(a)).split(separator: " ").map(String.init)
            let items = loadClipboard().filter { c in
                let h = PaletteSearch.fold((c.text ?? "") + " " + (c.ocrText ?? ""))
                return words.allSatisfy { h.contains($0) }
            }.prefix(limit(a))
            if items.isEmpty { return text("Nothing found in the clipboard history.") }
            return text(items.map { "- \(iso($0.date))\($0.sourceApp.map { " · \($0)" } ?? "")\n  \(($0.text ?? $0.ocrText ?? "").prefix(600))" }.joined(separator: "\n"))
        },
        Tool(name: "mac_status", source: .system,
             description: "How the user's Mac is doing right now: CPU load, memory in use, free disk, battery, temperature state, uptime and the processes using the most CPU and memory.",
             properties: [:], required: [], readOnly: true) { _ in text(MacStatus.report()) },
        Tool(name: "agent_usage", source: .usage,
             description: "Token usage of Claude Code, Codex and Gemini CLI on this Mac (today, last 7 days, by model and project), estimated API cost for Claude, and Codex plan limits with reset times. Read from local logs.",
             properties: [:], required: [], readOnly: true) { _ in text(usageReport()) },
        Tool(name: "save_to_memory", source: .write,
             description: "Save a text or link to the user's Menew memory so they can find it later. Needs Menew to be open.",
             properties: ["text": ["type": "string"], "title": ["type": "string"]], required: ["text"], readOnly: false) { a in
            post(["action": "memory", "text": a["text"] as? String ?? "", "title": a["title"] as? String ?? ""])
        },
        Tool(name: "add_note", source: .write, description: "Create a new Menew note (Markdown). The first line is the title. Needs Menew to be open.",
             properties: ["text": ["type": "string"]], required: ["text"], readOnly: false) { a in
            post(["action": "note", "text": a["text"] as? String ?? ""])
        },
        Tool(name: "notify_user", source: .write,
             description: "Show a short message to the user in the Mac's notch and as a notification, e.g. when a long task is done or you need their attention. Needs Menew to be open.",
             properties: ["message": ["type": "string"]], required: ["message"], readOnly: false) { a in
            post(["action": "notify", "text": String((a["message"] as? String ?? "").prefix(300))])
        },
    ]

    private static func post(_ info: [String: String]) -> [String: Any] {
        let id = Bundle.main.bundleIdentifier ?? "com.matheusquost.menew"
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else {
            return text("Menew is not open. Ask the user to open Menew and try again.", error: true)
        }
        guard !(info["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text("Empty text.", error: true) }
        DistributedNotificationCenter.default().postNotificationName(bridge, object: nil, userInfo: info, deliverImmediately: true)
        return text("Done.")
    }

    // MARK: Os arquivos do Menew (só leitura)

    private static func decoder(iso: Bool) -> JSONDecoder {
        let d = JSONDecoder()
        if iso { d.dateDecodingStrategy = .iso8601 }
        return d
    }

    static func loadMemory() -> [MemoryItem] {
        guard let data = try? Data(contentsOf: base.appendingPathComponent("memory/memory.json")) else { return [] }
        return ((try? decoder(iso: true).decode([MemoryItem].self, from: data)) ?? []).sorted { $0.date > $1.date }
    }

    /// Nunca as protegidas (o texto fica nas Chaves) nem as de senhas
    static func loadNotes() -> [Note] {
        guard let data = try? Data(contentsOf: base.appendingPathComponent("notes.json")) else { return [] }
        return ((try? decoder(iso: false).decode([Note].self, from: data)) ?? [])
            .filter { !$0.secure && $0.kind != .passwords }.sorted { $0.updated > $1.updated }
    }

    static func loadRecordings() -> [Recording] {
        guard let data = try? Data(contentsOf: base.appendingPathComponent("recordings/recordings.json")) else { return [] }
        return ((try? decoder(iso: true).decode([Recording].self, from: data)) ?? []).filter { $0.status == .ready }.sorted { $0.date > $1.date }
    }

    static func loadClipboard() -> [ClipItem] {
        guard let data = try? Data(contentsOf: base.appendingPathComponent("history.json")) else { return [] }
        return ((try? decoder(iso: false).decode([ClipItem].self, from: data)) ?? [])
            .filter { $0.secretNoteID == nil && ($0.text != nil || $0.ocrText != nil) }.sorted { $0.date > $1.date }
    }

    static func usageReport() -> String {
        let r = AgentUsageScanner().scanNow()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date()), week = cal.date(byAdding: .day, value: -6, to: today)!
        var out = "# AI agent usage on this Mac\n"
        for agent in AgentKind.allCases {
            let recs = r.records.filter { $0.agent == agent }
            guard !recs.isEmpty || agent.isInstalled else { continue }
            func sum(_ since: Date) -> (Int, Double) {
                recs.filter { $0.date >= since }.reduce((0, 0.0)) { ($0.0 + $1.total, $0.1 + (AgentPricing.cost($1) ?? 0)) }
            }
            let (t, c) = sum(today), (w, cw) = sum(week)
            out += "\n## \(agent.name)\nToday: \(t.formatted()) tokens" + (agent == .claude ? String(format: " (~$%.2f at API prices)", c) : "")
            out += "\nLast 7 days: \(w.formatted()) tokens" + (agent == .claude ? String(format: " (~$%.2f)", cw) : "")
            var byModel: [String: Int] = [:]
            var byProject: [String: Int] = [:]
            for x in recs where x.date >= week { byModel[x.model, default: 0] += x.total; byProject[x.project, default: 0] += x.total }
            if !byModel.isEmpty { out += "\nBy model (7 days): " + byModel.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key) \($0.value.formatted())" }.joined(separator: ", ") }
            if !byProject.isEmpty { out += "\nBy project (7 days): " + byProject.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) \($0.value.formatted())" }.joined(separator: ", ") }
            if agent == .codex, !r.codexLimits.isEmpty {
                out += "\nPlan limits" + (r.codexPlan.map { " (\($0))" } ?? "") + ": " + r.codexLimits.map { w in
                    "\(w.windowMinutes.map { "\($0 / 60)h window" } ?? "window") \(Int(w.usedPercent))% used" + (w.resetsAt.map { ", resets \(iso($0))" } ?? "")
                }.joined(separator: "; ")
            }
        }
        return out
    }
}

/// Recados do servidor MCP para o Menew aberto (guardar, criar nota, avisar). Cada um aparece num aviso.
@MainActor
enum MCPBridge {
    private static var observer: NSObjectProtocol?

    static func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: MCPServer.bridge, object: nil, queue: .main) { n in
            let info = (n.userInfo as? [String: String]) ?? [:]
            MainActor.assumeIsolated { handle(info) }
        }
    }

    static func handle(_ info: [String: String]) {
        let text = (info["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch info["action"] {
        case "memory" where MCPSource.write.isOn:
            let title = info["title"].flatMap { $0.isEmpty ? nil : $0 }
            MemoryStore.shared.add(text: title.map { "\($0)\n\n\(text)" } ?? text, origin: MemoryOrigin(app: L("Agente de IA")))
        case "note" where MCPSource.write.isOn:
            guard let app = NSApp.delegate as? AppDelegate else { return }
            _ = app.notes.create(text: String(text.prefix(100_000)))
            HUD.show(icon: "note.text.badge.plus", color: .yellow, text: L("Nota criada por um agente"))
        case "notify" where MCPSource.write.isOn:
            let t = String(text.prefix(300))
            if !NotchCenter.shared.show(icon: "sparkles", color: .purple, text: t, duration: 8) {
                HUD.show(icon: "sparkles", color: .purple, text: t, duration: 4)
            }
            Alerts.shared.notify(id: "menew.mcp.\(UUID().uuidString)", title: L("Recado de um agente"), body: t)
        default:
            break
        }
    }
}

/// Um resumo do Mac sem abrir o app inteiro (o servidor MCP é um processo à parte)
enum MacStatus {
    static func report() -> String {
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let total = ProcessInfo.processInfo.physicalMemory
        var lines = ["# Mac status"]
        lines.append(String(format: "CPU load (1/5/15 min): %.1f / %.1f / %.1f on %d cores", load[0], load[1], load[2], cores))
        if let used = memoryUsed() {
            lines.append("Memory: \(Fmt.memShort(used)) used of \(Fmt.memShort(total))")
        }
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let free = v.volumeAvailableCapacityForImportantUsage, let size = v.volumeTotalCapacity {
            lines.append("Disk: \(Fmt.bytes(free)) free of \(Fmt.bytes(Int64(size)))")
        }
        let batt = Shell.run("/usr/bin/pmset", ["-g", "batt"]).split(separator: "\n").dropFirst().first.map(String.init)
        if let batt, batt.contains("%") { lines.append("Battery: " + batt.split(separator: "\t").last.map(String.init)!.trimmingCharacters(in: .whitespaces)) }
        let thermal = ["nominal", "fair", "serious", "critical"][ProcessInfo.processInfo.thermalState.rawValue]
        lines.append("Thermal state: \(thermal)")
        let up = Int(ProcessInfo.processInfo.systemUptime)
        lines.append("Uptime: \(up / 86400)d \(up / 3600 % 24)h")
        let ps = Shell.run("/bin/ps", ["-Aceo", "pcpu=,rss=,comm=", "-r"]).split(separator: "\n").prefix(6)
        lines.append("\nTop processes (CPU %, memory):")
        for l in ps {
            let parts = l.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let kb = UInt64(parts[1]) else { continue }
            lines.append("- \(parts[2]): \(parts[0])% CPU, \(Fmt.memShort(kb * 1024))")
        }
        return lines.joined(separator: "\n")
    }

    private static func memoryUsed() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        return (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }
}

// MARK: Ligar nos apps

/// Onde cada app guarda a lista de servidores MCP. Claude Code e Codex têm comando próprio para isso
/// (o Menew usa o comando, para não brigar com o arquivo que eles reescrevem); os outros são um JSON simples.
enum MCPClient: String, CaseIterable, Identifiable {
    case claudeCode, codex, gemini, claudeDesktop, cursor
    var id: String { rawValue }

    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        case .claudeDesktop: "Claude Desktop"
        case .cursor: "Cursor"
        }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private var jsonConfig: URL? {
        switch self {
        case .gemini: Self.home.appendingPathComponent(".gemini/settings.json")
        case .claudeDesktop: Self.home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .cursor: Self.home.appendingPathComponent(".cursor/mcp.json")
        default: nil
        }
    }

    var isAvailable: Bool {
        let fm = FileManager.default
        switch self {
        case .claudeCode: return Self.cli("claude") != nil
        case .codex: return Self.cli("codex") != nil
        case .gemini: return fm.fileExists(atPath: Self.home.appendingPathComponent(".gemini").path)
        case .claudeDesktop: return fm.fileExists(atPath: "/Applications/Claude.app") || fm.fileExists(atPath: jsonConfig!.deletingLastPathComponent().path)
        case .cursor: return fm.fileExists(atPath: "/Applications/Cursor.app") || fm.fileExists(atPath: Self.home.appendingPathComponent(".cursor").path)
        }
    }

    var isInstalled: Bool {
        switch self {
        case .claudeCode:
            // Onde o Claude Code guarda a lista muda de versão para versão: pergunta a ele (leva ~1 s; chamar fora da tela)
            guard let c = Self.cli("claude") else { return false }
            return Self.exec(c, ["mcp", "get", "menew"]) == nil
        case .codex:
            let toml = (try? String(contentsOf: Self.home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)) ?? ""
            return toml.contains("[mcp_servers.menew]")
        default:
            guard let url = jsonConfig, let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return (obj["mcpServers"] as? [String: Any])?["menew"] != nil
        }
    }

    /// Os CLIs ficam fora do PATH de um app aberto pelo Finder: procura nos lugares de sempre
    static func cli(_ name: String) -> String? {
        let h = home.path
        return ["\(h)/.local/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "\(h)/.claude/local/\(name)", "\(h)/.npm-global/bin/\(name)"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var serverJSON: [String: Any] { ["command": AgentHooks.executable, "args": [MCPServer.flag]] }

    /// Para colar em qualquer outro app que fale MCP
    static var snippet: String {
        let obj: [String: Any] = ["mcpServers": ["menew": serverJSON]]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Liga ou desliga; devolve a mensagem de erro, se houver
    func set(_ on: Bool) -> String? {
        switch self {
        case .claudeCode:
            guard let c = Self.cli("claude") else { return L("Não achei o comando claude") }
            if on {
                _ = Self.exec(c, ["mcp", "remove", "--scope", "user", "menew"])
                return Self.exec(c, ["mcp", "add", "--scope", "user", "menew", "--", AgentHooks.executable, MCPServer.flag])
            }
            return Self.exec(c, ["mcp", "remove", "--scope", "user", "menew"])
        case .codex:
            guard let c = Self.cli("codex") else { return L("Não achei o comando codex") }
            if on {
                _ = Self.exec(c, ["mcp", "remove", "menew"])
                return Self.exec(c, ["mcp", "add", "menew", "--", AgentHooks.executable, MCPServer.flag])
            }
            return Self.exec(c, ["mcp", "remove", "menew"])
        default:
            guard let url = jsonConfig else { return nil }
            let fm = FileManager.default
            var obj: [String: Any] = [:]
            if let data = try? Data(contentsOf: url) {
                guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return L("O arquivo de configuração não é um JSON que o Menew consiga editar") }
                obj = o
                let backup = url.appendingPathExtension("menew-backup")
                if !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: url, to: backup) }
            }
            var servers = obj["mcpServers"] as? [String: Any] ?? [:]
            servers["menew"] = on ? Self.serverJSON : nil
            obj["mcpServers"] = servers
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]),
                  (try? data.write(to: url, options: .atomic)) != nil else { return L("Não consegui gravar o arquivo") }
            return nil
        }
    }

    /// Roda um CLI com um PATH de terminal (o do Codex é um script Node); nil se deu certo
    static func exec(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let err = Pipe()
        p.standardOutput = Pipe()
        p.standardError = err
        do { try p.run() } catch { return error.localizedDescription }
        p.waitUntilExit()
        if p.terminationStatus == 0 { return nil }
        let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? L("O comando falhou") : String(msg.prefix(200))
    }
}

/// Se cada app já tem o Menew na lista de MCP. Perguntar ao Claude Code leva um segundo, então é lido em segundo plano
@MainActor
final class MCPStatus: ObservableObject {
    static let shared = MCPStatus()
    @Published private(set) var installed: [MCPClient: Bool] = [:]
    @Published private(set) var busy: Set<MCPClient> = []
    @Published var error: String?

    func refresh() {
        Task.detached {
            let r = Dictionary(uniqueKeysWithValues: MCPClient.allCases.filter(\.isAvailable).map { ($0, $0.isInstalled) })
            await MainActor.run { MCPStatus.shared.installed = r }
        }
    }

    func set(_ c: MCPClient, _ on: Bool) {
        busy.insert(c)
        installed[c] = on
        Task.detached {
            let err = c.set(on)
            let now = c.isInstalled
            await MainActor.run {
                let s = MCPStatus.shared
                s.busy.remove(c)
                s.installed[c] = now
                s.error = err
            }
        }
    }
}
