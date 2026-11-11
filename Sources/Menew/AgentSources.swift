import Foundation
import SQLite3

/// O uso das outras ferramentas de IA (OpenCode, Kiro, Copilot CLI, Droid, Qwen Code, Amp, OpenClaw, Kimi, Goose, Pi),
/// lido dos arquivos que elas mesmas gravam no Mac. Cada fonte diz quais arquivos olhar e como ler um arquivo inteiro;
/// o scanner relê um arquivo só quando ele muda. Nada sai do Mac. O Cursor não guarda o uso no Mac (só no site dele).
struct AgentSource {
    let agent: AgentKind
    /// Arquivos (ou bancos SQLite) mexidos desde `cutoff`
    let files: (_ cutoff: Date) -> [URL]
    let parse: (_ url: URL) -> [UsageRecord]

    static let all: [AgentSource] = [
        AgentSource(agent: .opencode, files: OpenCodeLog.files, parse: OpenCodeLog.parse),
        AgentSource(agent: .kiro, files: KiroLog.files, parse: KiroLog.parse),
        AgentSource(agent: .copilot, files: CopilotLog.files, parse: CopilotLog.parse),
        AgentSource(agent: .droid, files: DroidLog.files, parse: DroidLog.parse),
        AgentSource(agent: .qwen, files: QwenLog.files, parse: QwenLog.parse),
        AgentSource(agent: .amp, files: AmpLog.files, parse: AmpLog.parse),
        AgentSource(agent: .openclaw, files: OpenClawLog.files, parse: OpenClawLog.parse),
        AgentSource(agent: .kimi, files: KimiLog.files, parse: KimiLog.parse),
        AgentSource(agent: .goose, files: GooseLog.files, parse: GooseLog.parse),
        AgentSource(agent: .pi, files: PiLog.files, parse: PiLog.parse),
    ]

    /// Quando o arquivo mudou; num banco SQLite, o `-wal` do lado muda antes do arquivo principal
    static func mtime(_ url: URL) -> Date {
        let fm = FileManager.default
        return [url.path, url.path + "-wal"].compactMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }.max() ?? .distantPast
    }
}

// MARK: Ajudantes

enum AgentFiles {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Os arquivos com estas extensões debaixo de `dir` (até `depth` pastas), mexidos desde `cutoff`
    static func find(_ dir: URL, ext: Set<String>, cutoff: Date, depth: Int = 6, suffix: String? = nil) -> [URL] {
        guard FileManager.default.fileExists(atPath: dir.path),
              let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in en {
            if en.level > depth { en.skipDescendants(); continue }
            guard ext.contains(url.pathExtension), suffix.map({ url.lastPathComponent.hasSuffix($0) }) ?? true else { continue }
            let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if m >= cutoff { out.append(url) }
        }
        return out
    }

    /// Um arquivo (banco SQLite) que existe e mudou desde `cutoff`
    static func existing(_ paths: [String], cutoff: Date) -> [URL] {
        paths.map { home.appendingPathComponent($0) }.filter {
            FileManager.default.fileExists(atPath: $0.path) && AgentSource.mtime($0) >= cutoff
        }
    }

    static func json(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    /// Cada linha de um JSONL como dicionário (as que não são JSON ficam de fora)
    static func lines(_ url: URL, contains marker: String? = nil) -> [[String: Any]] {
        guard let d = try? Data(contentsOf: url), let s = String(data: d, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap { line in
            if let marker, !line.contains(marker) { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? (v as? String).flatMap { Int($0) } ?? 0 }
    static func double(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap { Double($0) } }

    /// Datas em ISO 8601, em milissegundos ou em segundos
    static func date(_ v: Any?) -> Date? {
        if let s = v as? String {
            if let d = AgentDates.parse(s) { return d }
            if let n = Double(s) { return number(n) }
            // "2026-11-10 14:03:22" (SQLite)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.date(from: String(s.prefix(19)))
        }
        if let n = (v as? NSNumber)?.doubleValue { return number(n) }
        return nil
    }

    private static func number(_ n: Double) -> Date? {
        guard n > 0 else { return nil }
        return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)
    }

    static func dict(_ v: Any?) -> [String: Any] {
        if let d = v as? [String: Any] { return d }
        if let s = v as? String, let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] { return d }
        return [:]
    }
}

/// Leitura de um banco SQLite de outra ferramenta, só para ler e sem travar quem grava nele
enum SQLiteReader {
    static func query(_ url: URL, _ sql: String) -> [[Any?]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db); return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [[Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let n = sqlite3_column_count(stmt)
            rows.append((0..<n).map { i -> Any? in
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: NSNumber(value: sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT: NSNumber(value: sqlite3_column_double(stmt, i))
                case SQLITE_TEXT: sqlite3_column_text(stmt, i).map { String(cString: $0) }
                default: nil
                }
            })
        }
        return rows
    }

    static func tables(_ url: URL) -> Set<String> {
        Set(query(url, "SELECT name FROM sqlite_master WHERE type IN ('table','view')").compactMap { $0.first as? String })
    }

    static func columns(_ url: URL, _ table: String) -> Set<String> {
        Set(query(url, "PRAGMA table_info(\(table))").compactMap { $0.count > 1 ? $0[1] as? String : nil })
    }
}

// MARK: OpenCode

/// `~/.local/share/opencode/opencode.db` (versões novas, SQLite) ou `storage/message/<sessão>/<mensagem>.json` (antigas).
/// Cada resposta tem `tokens` {input, output, reasoning, cache {read, write}}, `cost` em US$ e `time.created` em ms.
enum OpenCodeLog {
    static let root = AgentFiles.home.appendingPathComponent(".local/share/opencode")

    static func files(_ cutoff: Date) -> [URL] {
        let dbs = ["opencode.db", "opencode-stable.db"].map { root.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) && AgentSource.mtime($0) >= cutoff }
        return dbs + AgentFiles.find(root.appendingPathComponent("storage/message"), ext: ["json"], cutoff: cutoff, depth: 2)
    }

    static func parse(_ url: URL) -> [UsageRecord] {
        if url.pathExtension == "db" { return parseDB(url) }
        guard let d = AgentFiles.json(url) else { return [] }
        return record(d, directory: nil).map { [$0] } ?? []
    }

    static func parseDB(_ url: URL) -> [UsageRecord] {
        let tables = SQLiteReader.tables(url)
        let session = ["session", "session_v2"].first { tables.contains($0) && SQLiteReader.columns(url, $0).contains("directory") }
        let join = session.map { " LEFT JOIN \($0) s ON s.id = m.session_id" } ?? ""
        let dir = session == nil ? "NULL" : "s.directory"
        var sql: String?
        if tables.contains("session_message") {
            sql = "SELECT m.data, \(dir) FROM session_message m\(join) WHERE m.type = 'assistant'"
        } else if tables.contains("message") {
            sql = "SELECT m.data, \(dir) FROM message m\(join) WHERE m.data LIKE '%\"assistant\"%'"
        }
        guard let sql else { return [] }
        return SQLiteReader.query(url, sql).compactMap { row in
            record(AgentFiles.dict(row.first ?? nil), directory: row.count > 1 ? row[1] as? String : nil)
        }
    }

    static func record(_ d: [String: Any], directory: String?) -> UsageRecord? {
        guard (d["role"] as? String ?? "assistant") == "assistant", let t = d["tokens"] as? [String: Any],
              let date = AgentFiles.date((d["time"] as? [String: Any])?["created"]) else { return nil }
        let model = d["modelID"] as? String ?? (d["model"] as? [String: Any])?["id"] as? String ?? "opencode"
        let cwd = directory ?? (d["path"] as? [String: Any])?["root"] as? String ?? (d["path"] as? [String: Any])?["cwd"] as? String
        var r = UsageRecord(date: date, agent: .opencode, model: model, project: AgentDates.project(cwd))
        let cache = t["cache"] as? [String: Any] ?? [:]
        r.input = AgentFiles.int(t["input"])
        r.output = AgentFiles.int(t["output"]) + AgentFiles.int(t["reasoning"])
        r.cacheRead = AgentFiles.int(cache["read"])
        r.cacheWrite5m = AgentFiles.int(cache["write"])
        if let c = AgentFiles.double(d["cost"]), c > 0 { r.reportedCost = c }
        r.key = (d["id"] as? String).map { "opencode:" + $0 }
        return r.total > 0 || r.reportedCost != nil ? r : nil
    }
}

// MARK: Kiro

/// Kiro (o editor) grava cada pedido em `~/.kiro/sessions/<pasta>/sess_<id>/messages.jsonl`: as linhas `usage_summary`
/// dizem quantos créditos ele gastou (sem tokens). O Kiro CLI grava `~/.kiro/sessions/cli/<id>.json` com os tokens
/// e os créditos de cada pedido.
enum KiroLog {
    static let sessions = AgentFiles.home.appendingPathComponent(".kiro/sessions")
    /// Preço do crédito extra do Kiro (US$), para ter uma ideia do custo
    static let creditPrice = 0.04

    static func files(_ cutoff: Date) -> [URL] {
        AgentFiles.find(sessions, ext: ["jsonl"], cutoff: cutoff, depth: 3).filter { $0.lastPathComponent == "messages.jsonl" }
            + AgentFiles.find(sessions.appendingPathComponent("cli"), ext: ["json"], cutoff: cutoff, depth: 1)
    }

    static func parse(_ url: URL) -> [UsageRecord] {
        url.pathExtension == "json" ? parseCLI(url) : parseIDE(url)
    }

    static func parseIDE(_ url: URL) -> [UsageRecord] {
        let meta = AgentFiles.json(url.deletingLastPathComponent().appendingPathComponent("session.json")) ?? [:]
        let cwd = (meta["workspacePaths"] as? [String])?.first ?? (meta["rootPaths"] as? [String])?.first
        let model = meta["modelId"] as? String ?? "auto"
        return AgentFiles.lines(url, contains: "usage_summary").compactMap { line in
            let p = line["payload"] as? [String: Any] ?? [:]
            guard p["type"] as? String == "usage_summary", let date = AgentFiles.date(line["timestamp"]) else { return nil }
            let credits = (p["promptTurnSummaries"] as? [[String: Any]] ?? [])
                .filter { ($0["unit"] as? String ?? "credit") == "credit" }.compactMap { AgentFiles.double($0["usage"]) }.reduce(0, +)
            guard credits > 0 else { return nil }
            var r = UsageRecord(date: date, agent: .kiro, model: model == "auto" ? "Kiro Auto" : model, project: AgentDates.project(cwd), client: .ide)
            r.credits = credits
            r.reportedCost = credits * creditPrice
            return r
        }
    }

    static func parseCLI(_ url: URL) -> [UsageRecord] {
        guard let d = AgentFiles.json(url) else { return [] }
        let state = d["session_state"] as? [String: Any] ?? [:]
        let model = ((state["rts_model_state"] as? [String: Any])?["model_info"] as? [String: Any])?["model_id"] as? String ?? "auto"
        let turns = (state["conversation_metadata"] as? [String: Any])?["user_turn_metadatas"] as? [[String: Any]] ?? []
        let fallback = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return turns.compactMap { t in
            var r = UsageRecord(date: AgentFiles.date(t["end_timestamp"]) ?? fallback, agent: .kiro,
                                model: model == "auto" ? "Kiro Auto" : model, project: AgentDates.project(d["cwd"] as? String))
            r.input = AgentFiles.int(t["input_token_count"])
            r.output = AgentFiles.int(t["output_token_count"])
            r.cacheRead = AgentFiles.int(t["cache_read_input_token_count"])
            r.cacheWrite5m = AgentFiles.int(t["cache_write_input_token_count"])
            r.credits = (t["metering_usage"] as? [[String: Any]] ?? [])
                .filter { ($0["unit"] as? String ?? "credit").hasPrefix("credit") }.compactMap { AgentFiles.double($0["value"]) }.reduce(0, +)
            if r.credits > 0 { r.reportedCost = r.credits * creditPrice }
            return r.total > 0 || r.credits > 0 ? r : nil
        }
    }
}

// MARK: Copilot CLI

/// `~/.copilot/session-store.db`, tabela `assistant_usage_events`: os tokens de cada resposta e o custo em nano-AIU
enum CopilotLog {
    static func files(_ cutoff: Date) -> [URL] { AgentFiles.existing([".copilot/session-store.db"], cutoff: cutoff) }

    static func parse(_ url: URL) -> [UsageRecord] {
        let cols = SQLiteReader.columns(url, "assistant_usage_events")
        guard !cols.isEmpty else { return [] }
        let model = cols.contains("copilot_usage_model") ? "COALESCE(e.copilot_usage_model, e.model)" : "e.model"
        let aiu = cols.contains("total_nano_aiu") ? "e.total_nano_aiu" : "NULL"
        let join = SQLiteReader.columns(url, "sessions").contains("cwd") ? " LEFT JOIN sessions s ON s.id = e.session_id" : ""
        let cwd = join.isEmpty ? "NULL" : "s.cwd"
        let sql = """
        SELECT e.id, e.created_at, \(model), e.input_tokens, e.output_tokens, e.cache_read_tokens, e.cache_write_tokens,
               e.reasoning_tokens, \(aiu), \(cwd) FROM assistant_usage_events e\(join)
        """
        return SQLiteReader.query(url, sql).compactMap { row in
            guard row.count == 10, let date = AgentFiles.date(row[1]) else { return nil }
            var r = UsageRecord(date: date, agent: .copilot, model: row[2] as? String ?? "copilot", project: AgentDates.project(row[9] as? String))
            let cacheRead = AgentFiles.int(row[5]), cacheWrite = AgentFiles.int(row[6])
            r.input = max(0, AgentFiles.int(row[3]) - cacheRead - cacheWrite)   // a entrada já inclui o cache
            r.output = AgentFiles.int(row[4]) + AgentFiles.int(row[7])
            r.cacheRead = cacheRead
            r.cacheWrite5m = cacheWrite
            if let n = AgentFiles.double(row[8]), n > 0 { r.reportedCost = n / 1e11 }
            r.key = "copilot:\(row[0].map { "\($0)" } ?? UUID().uuidString)"
            return r.total > 0 ? r : nil
        }
    }
}

// MARK: Droid (Factory)

/// `~/.factory/sessions/**/<id>.settings.json`: o total da sessão em `tokenUsage` (o Droid não grava por resposta).
/// Fica no dia em que a sessão começou, para uma sessão que passa da meia-noite não ser contada duas vezes.
enum DroidLog {
    static func files(_ cutoff: Date) -> [URL] {
        AgentFiles.find(AgentFiles.home.appendingPathComponent(".factory/sessions"), ext: ["json"], cutoff: cutoff, depth: 3, suffix: ".settings.json")
    }

    static func parse(_ url: URL) -> [UsageRecord] {
        guard let d = AgentFiles.json(url), let t = d["tokenUsage"] as? [String: Any] else { return [] }
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        let model = (d["effectiveFactoryRouterModel"] as? [String: Any])?["modelId"] as? String ?? d["model"] as? String ?? "droid"
        let folder = url.deletingLastPathComponent().lastPathComponent
        let project = folder == "sessions" ? "Droid" : DroidLog.project(folder)
        var r = UsageRecord(date: AgentFiles.date(d["providerLockTimestamp"]) ?? created, agent: .droid, model: model, project: project)
        r.input = AgentFiles.int(t["inputTokens"])
        r.output = AgentFiles.int(t["outputTokens"]) + AgentFiles.int(t["thinkingTokens"])
        r.cacheRead = AgentFiles.int(t["cacheReadTokens"])
        r.cacheWrite5m = AgentFiles.int(t["cacheCreationTokens"])
        return r.total > 0 ? [r] : []
    }

    /// "-Users-ana-apps-menew" → "menew"
    static func project(_ slug: String) -> String {
        slug.split(separator: "-").last.map(String.init) ?? slug
    }
}

// MARK: Qwen Code

/// `~/.qwen/projects/<projeto>/chats/*.jsonl`: linhas `assistant` com `usageMetadata` (como o Gemini)
enum QwenLog {
    static func files(_ cutoff: Date) -> [URL] {
        AgentFiles.find(AgentFiles.home.appendingPathComponent(".qwen/projects"), ext: ["jsonl"], cutoff: cutoff, depth: 3)
    }

    static func parse(_ url: URL) -> [UsageRecord] {
        let folder = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        return AgentFiles.lines(url, contains: "usageMetadata").compactMap { line in
            guard line["type"] as? String == "assistant", let u = line["usageMetadata"] as? [String: Any],
                  let date = AgentFiles.date(line["timestamp"]) else { return nil }
            var r = UsageRecord(date: date, agent: .qwen, model: line["model"] as? String ?? "qwen", project: DroidLog.project(folder))
            let prompt = AgentFiles.int(u["promptTokenCount"]), cached = AgentFiles.int(u["cachedContentTokenCount"])
            let out = AgentFiles.int(u["candidatesTokenCount"]), thoughts = AgentFiles.int(u["thoughtsTokenCount"])
            let total = AgentFiles.int(u["totalTokenCount"])
            r.input = max(0, prompt - cached)
            r.cacheRead = cached
            // O total diz se o pensamento já está dentro da resposta
            r.output = total > 0 && prompt + out >= total ? out : out + thoughts
            return r.total > 0 ? r : nil
        }
    }
}

// MARK: Amp

/// `~/.local/share/amp/threads/*.json`: cada resposta com `usage` {model, inputTokens, outputTokens, cache…, credits}
enum AmpLog {
    static func files(_ cutoff: Date) -> [URL] {
        AgentFiles.find(AgentFiles.home.appendingPathComponent(".local/share/amp/threads"), ext: ["json"], cutoff: cutoff, depth: 1)
    }

    static func parse(_ url: URL) -> [UsageRecord] {
        guard let d = AgentFiles.json(url) else { return [] }
        let created = AgentFiles.date(d["created"])
        let cwd = ((d["env"] as? [String: Any])?["initial"] as? [String: Any])?["trees"].flatMap { ($0 as? [[String: Any]])?.first?["displayName"] as? String }
        return (d["messages"] as? [[String: Any]] ?? []).compactMap { m in
            guard m["role"] as? String == "assistant", let u = m["usage"] as? [String: Any],
                  let date = AgentFiles.date(u["timestamp"]) ?? created else { return nil }
            var r = UsageRecord(date: date, agent: .amp, model: u["model"] as? String ?? "amp", project: cwd ?? "Amp")
            r.input = AgentFiles.int(u["inputTokens"])
            r.output = AgentFiles.int(u["outputTokens"])
            r.cacheRead = AgentFiles.int(u["cacheReadInputTokens"])
            r.cacheWrite5m = AgentFiles.int(u["cacheCreationInputTokens"])
            // O crédito do Amp vale US$ 1
            if let c = AgentFiles.double(u["credits"]), c > 0 { r.credits = c; r.reportedCost = c }
            return r.total > 0 ? r : nil
        }
    }
}

// MARK: OpenClaw

/// `~/.openclaw/agents/<agente>/sessions/*.jsonl` (e, nas versões novas, o mesmo evento em
/// `agent/openclaw-agent.sqlite`): linhas `message` do assistente com `usage` {input, output, cacheRead, cacheWrite, cost.total}
enum OpenClawLog {
    static let root = AgentFiles.home.appendingPathComponent(".openclaw/agents")

    static func files(_ cutoff: Date) -> [URL] {
        let agents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let dbs = agents.map { $0.appendingPathComponent("agent/openclaw-agent.sqlite") }
            .filter { FileManager.default.fileExists(atPath: $0.path) && AgentSource.mtime($0) >= cutoff }
        return dbs + agents.flatMap { AgentFiles.find($0.appendingPathComponent("sessions"), ext: ["jsonl"], cutoff: cutoff, depth: 1) }
    }

    static func parse(_ url: URL) -> [UsageRecord] {
        if url.pathExtension == "sqlite" {
            guard SQLiteReader.columns(url, "transcript_events").contains("event_json") else { return [] }
            // Os eventos comprimidos (zstd) ficam de fora: os mesmos estão nos .jsonl
            return SQLiteReader.query(url, "SELECT event_json, created_at FROM transcript_events WHERE event_json IS NOT NULL AND event_json LIKE '%\"usage\"%'")
                .compactMap { record(AgentFiles.dict($0.first ?? nil), fallback: AgentFiles.date($0.count > 1 ? $0[1] : nil)) }
        }
        return AgentFiles.lines(url, contains: "\"usage\"").compactMap { record($0, fallback: nil) }
    }

    static func record(_ e: [String: Any], fallback: Date?) -> UsageRecord? {
        guard e["type"] as? String == "message", let m = e["message"] as? [String: Any], m["role"] as? String == "assistant",
              let u = m["usage"] as? [String: Any], let date = AgentFiles.date(m["timestamp"]) ?? AgentFiles.date(e["timestamp"]) ?? fallback else { return nil }
        var r = UsageRecord(date: date, agent: .openclaw, model: m["model"] as? String ?? "openclaw", project: "OpenClaw")
        r.input = AgentFiles.int(u["input"])
        r.output = AgentFiles.int(u["output"])
        r.cacheRead = AgentFiles.int(u["cacheRead"])
        r.cacheWrite5m = AgentFiles.int(u["cacheWrite"])
        if let c = AgentFiles.double((u["cost"] as? [String: Any])?["total"]), c > 0 { r.reportedCost = c }
        r.key = (e["id"] as? String).map { "openclaw:\($0):\(Int(date.timeIntervalSince1970 * 1000))" }
        return r.total > 0 ? r : nil
    }
}

// MARK: Kimi

/// Kimi CLI: `~/.kimi/sessions/<grupo>/<sessão>/wire.jsonl`, linhas `StatusUpdate` com `token_usage` (o modelo vem do
/// `~/.kimi/config.json`). Kimi Code: `~/.kimi-code/sessions/<pasta>/<sessão>/agents/<agente>/wire.jsonl`, linhas `usage.record`.
enum KimiLog {
    static func files(_ cutoff: Date) -> [URL] {
        [".kimi/sessions", ".kimi-code/sessions"].flatMap {
            AgentFiles.find(AgentFiles.home.appendingPathComponent($0), ext: ["jsonl"], cutoff: cutoff, depth: 5)
        }.filter { $0.lastPathComponent == "wire.jsonl" }
    }

    static func parse(_ url: URL) -> [UsageRecord] {
        url.path.contains("/.kimi-code/") ? parseCode(url) : parseCLI(url)
    }

    static func parseCLI(_ url: URL) -> [UsageRecord] {
        let model = AgentFiles.json(AgentFiles.home.appendingPathComponent(".kimi/config.json"))?["model"] as? String ?? "kimi-for-coding"
        // Cada mensagem pode aparecer mais de uma vez enquanto cresce: fica a maior
        var byID: [String: UsageRecord] = [:], loose: [UsageRecord] = []
        for line in AgentFiles.lines(url, contains: "token_usage") {
            guard let m = line["message"] as? [String: Any], m["type"] as? String == "StatusUpdate",
                  let p = m["payload"] as? [String: Any], let u = p["token_usage"] as? [String: Any],
                  let date = AgentFiles.date(line["timestamp"]) else { continue }
            var r = UsageRecord(date: date, agent: .kimi, model: model, project: "Kimi")
            r.input = AgentFiles.int(u["input_other"])
            r.output = AgentFiles.int(u["output"])
            r.cacheRead = AgentFiles.int(u["input_cache_read"])
            r.cacheWrite5m = AgentFiles.int(u["input_cache_creation"])
            guard r.total > 0 else { continue }
            if let id = p["message_id"] as? String {
                if r.total >= (byID[id]?.total ?? 0) { byID[id] = r }
            } else { loose.append(r) }
        }
        return Array(byID.values) + loose
    }

    static func parseCode(_ url: URL) -> [UsageRecord] {
        AgentFiles.lines(url, contains: "usage.record").compactMap { line in
            guard line["type"] as? String == "usage.record", (line["usageScope"] as? String ?? "turn") == "turn",
                  let u = line["usage"] as? [String: Any], let date = AgentFiles.date(line["time"]) else { return nil }
            let model = (line["model"] as? String ?? "kimi").replacingOccurrences(of: "kimi-code/", with: "")
            var r = UsageRecord(date: date, agent: .kimi, model: model, project: "Kimi")
            r.input = AgentFiles.int(u["inputOther"])
            r.output = AgentFiles.int(u["output"])
            r.cacheRead = AgentFiles.int(u["inputCacheRead"])
            r.cacheWrite5m = AgentFiles.int(u["inputCacheCreation"])
            return r.total > 0 ? r : nil
        }
    }
}

// MARK: Goose

/// `sessions.db`, tabela `sessions`: o total de cada sessão (sem cache), no dia em que ela começou
enum GooseLog {
    static func files(_ cutoff: Date) -> [URL] {
        AgentFiles.existing([".local/share/goose/sessions/sessions.db", "Library/Application Support/goose/sessions/sessions.db"], cutoff: cutoff)
    }

    static func parse(_ url: URL) -> [UsageRecord] {
        let cols = SQLiteReader.columns(url, "sessions")
        guard cols.contains("created_at") else { return [] }
        func pick(_ names: String...) -> String {
            let have = names.filter(cols.contains)
            return have.isEmpty ? "0" : "COALESCE(\(have.joined(separator: ", ")), 0)"
        }
        let model = cols.contains("model_config_json") ? "model_config_json" : "NULL"
        let dir = cols.contains("working_dir") ? "working_dir" : "NULL"
        let sql = "SELECT id, created_at, \(model), \(pick("accumulated_input_tokens", "input_tokens")), \(pick("accumulated_output_tokens", "output_tokens")), \(dir) FROM sessions"
        return SQLiteReader.query(url, sql).compactMap { row in
            guard row.count == 6, let date = AgentFiles.date(row[1]) else { return nil }
            let model = AgentFiles.dict(row[2])["model_name"] as? String ?? "goose"
            var r = UsageRecord(date: date, agent: .goose, model: model, project: AgentDates.project(row[5] as? String))
            r.input = AgentFiles.int(row[3])
            r.output = AgentFiles.int(row[4])
            r.key = "goose:\(row[0].map { "\($0)" } ?? "")"
            return r.total > 0 ? r : nil
        }
    }
}

// MARK: Pi (e agentes feitos a partir dele)

/// O Pi grava cada sessão em `~/.pi/agent/sessions/--<pasta>--/<data>_<id>.jsonl`: a primeira linha (`session`) tem o
/// `cwd`; as linhas `message` do assistente têm `usage` {input, output, cacheRead, cacheWrite, cost.total} e `timestamp`
/// em ms. Agentes feitos a partir do Pi trocam o nome da pasta (`~/.<nome>/agent`) e alguns guardam as mesmas linhas num
/// `sessions.db` (tabela `session_entries`): o Menew procura os dois formatos nas pastas ocultas da sua pasta pessoal.
enum PiLog {
    /// As pastas `agent` com sessões no formato do Pi
    static func roots() -> [URL] {
        let fm = FileManager.default
        let hidden = ((try? fm.contentsOfDirectory(atPath: AgentFiles.home.path)) ?? []).filter { $0.hasPrefix(".") && $0.count > 1 }
        return hidden.map { AgentFiles.home.appendingPathComponent($0).appendingPathComponent("agent") }.filter {
            fm.fileExists(atPath: $0.appendingPathComponent("sessions.db").path)
                || fm.fileExists(atPath: $0.appendingPathComponent("sessions").path)
        }
    }

    static func files(_ cutoff: Date) -> [URL] {
        roots().flatMap { root -> [URL] in
            let db = root.appendingPathComponent("sessions.db")
            let dbs = FileManager.default.fileExists(atPath: db.path) && AgentSource.mtime(db) >= cutoff ? [db] : []
            return dbs + AgentFiles.find(root.appendingPathComponent("sessions"), ext: ["jsonl"], cutoff: cutoff, depth: 2)
        }
    }

    static func parse(_ url: URL) -> [UsageRecord] {
        if url.pathExtension == "db" {
            guard SQLiteReader.columns(url, "session_entries").contains("payload_json") else { return [] }
            let join = SQLiteReader.columns(url, "sessions").contains("cwd") ? " LEFT JOIN sessions s ON s.id = e.session_id" : ""
            let sql = "SELECT e.session_id, e.payload_json, \(join.isEmpty ? "NULL" : "s.cwd") FROM session_entries e\(join) WHERE e.kind = 'message' AND e.payload_json LIKE '%\"usage\"%'"
            return SQLiteReader.query(url, sql).compactMap { row in
                guard row.count == 3 else { return nil }
                return record(AgentFiles.dict(row[1]), session: row[0] as? String ?? "", cwd: row[2] as? String)
            }
        }
        var cwd: String?, session = url.deletingPathExtension().lastPathComponent
        var out: [UsageRecord] = []
        for line in AgentFiles.lines(url) {
            if line["type"] as? String == "session" {
                cwd = line["cwd"] as? String
                if let id = line["id"] as? String { session = id }
            } else if let r = record(line, session: session, cwd: cwd) {
                out.append(r)
            }
        }
        return out
    }

    static func record(_ e: [String: Any], session: String, cwd: String?) -> UsageRecord? {
        guard e["type"] as? String ?? "message" == "message", let m = e["message"] as? [String: Any], m["role"] as? String == "assistant",
              let u = m["usage"] as? [String: Any], let date = AgentFiles.date(m["timestamp"]) ?? AgentFiles.date(e["timestamp"]) else { return nil }
        let model = m["responseModel"] as? String ?? m["model"] as? String ?? "pi"
        var r = UsageRecord(date: date, agent: .pi, model: model, project: AgentDates.project(cwd))
        r.input = AgentFiles.int(u["input"])
        r.output = AgentFiles.int(u["output"])
        r.cacheRead = AgentFiles.int(u["cacheRead"])
        let write1h = AgentFiles.int(u["cacheWrite1h"])
        r.cacheWrite5m = max(0, AgentFiles.int(u["cacheWrite"]) - write1h)
        r.cacheWrite1h = write1h
        if let c = AgentFiles.double((u["cost"] as? [String: Any])?["total"]), c > 0 { r.reportedCost = c }
        r.key = (e["id"] as? String).map { "pi:\(session):\($0)" }
        return r.total > 0 ? r : nil
    }
}
