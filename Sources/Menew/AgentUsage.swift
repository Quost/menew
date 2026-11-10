import AppKit
import Foundation
import Security
import SwiftUI

/// Agentes de IA no terminal (Claude Code, Codex, Gemini CLI): quanto você usou e quanto falta dos limites.
/// Tudo vem dos registros que cada ferramenta já grava no Mac; nada sai do Mac, com uma exceção opcional
/// (a % do plano do Claude, que só a Anthropic sabe e vem desligada).
enum AgentKind: String, CaseIterable, Identifiable, Codable {
    case claude, codex, gemini
    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        }
    }

    /// Nome curto para o notch e os avisos
    var short: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        }
    }

    var icon: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkle"
        }
    }

    var color: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.25, green: 0.55, blue: 0.95)
        case .gemini: Color(red: 0.55, green: 0.42, blue: 0.95)
        }
    }

    /// A pasta onde a ferramenta guarda as coisas (existir = está instalada neste Mac)
    var home: URL {
        let h = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude: return h.appendingPathComponent(".claude", isDirectory: true)
        case .codex: return h.appendingPathComponent(".codex", isDirectory: true)
        case .gemini: return h.appendingPathComponent(".gemini", isDirectory: true)
        }
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: home.path) }
}

/// Uma resposta do modelo: os tokens gastos nela
struct UsageRecord: Equatable {
    var date: Date
    var agent: AgentKind
    var model: String
    var project: String
    /// Entrada que não veio do cache
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0

    var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }
}

/// Uma janela de limite do plano ("5 horas", "semana"), com quanto já foi usado e quando zera
struct RateWindow: Equatable, Identifiable {
    var id: String { label }
    var label: String
    var usedPercent: Double
    var resetsAt: Date?
    var windowMinutes: Int?
    /// Quando o número foi lido (o Codex só atualiza enquanto você usa)
    var asOf: Date

    /// Para o notch: "5 h", "Sem.", "Mês"; janelas por modelo ("Semana · Opus") ficam com o nome do modelo
    var short: String {
        if let r = label.range(of: " · ") { return String(label[r.upperBound...]) }
        switch windowMinutes ?? 0 {
        case 300: return "5 h"
        case 1440: return L("Dia")
        case 10080: return L("Sem.")
        case 40000...46000: return L("Mês")
        default: return label
        }
    }

    /// Nome da janela pelos minutos: 300 → "5 horas", 10080 → "Semana"
    static func label(minutes: Int?) -> String {
        guard let m = minutes, m > 0 else { return L("Limite") }
        switch m {
        case 300: return L("5 horas")
        case 1440: return L("Dia")
        case 10080: return L("Semana")
        case 40000...46000: return L("Mês")
        default: return m % 1440 == 0 ? L("%d dias", m / 1440) : (m % 60 == 0 ? L("%d horas", m / 60) : L("%d min", m))
        }
    }

    /// Previsão pelo ritmo desde o início da janela: quando chega a 100%, se chegar antes de zerar.
    /// nil quando ainda é cedo para dizer, ou quando dá folga até o reset.
    func forecast(now: Date = Date()) -> Date? {
        guard let resetsAt, let windowMinutes, usedPercent >= 5, usedPercent < 100 else { return nil }
        let start = resetsAt.addingTimeInterval(-Double(windowMinutes) * 60)
        let elapsed = now.timeIntervalSince(start)
        guard elapsed > 10 * 60 else { return nil }
        let perSecond = usedPercent / elapsed
        let hits = now.addingTimeInterval((100 - usedPercent) / perSecond)
        return hits < resetsAt ? hits : nil
    }
}

// MARK: Leitura dos registros

/// Busca em bytes, sem montar String: os registros do Claude Code passam de centenas de MB num mês
enum Bytes {
    static func find(_ needle: [UInt8], in buf: UnsafeRawBufferPointer, from: Int = 0) -> Int? {
        guard let base = buf.baseAddress, from >= 0, buf.count - from >= needle.count else { return nil }
        return needle.withUnsafeBytes { n -> Int? in
            guard let p = memmem(base + from, buf.count - from, n.baseAddress!, n.count) else { return nil }
            return base.distance(to: UnsafeRawPointer(p))
        }
    }

    /// O valor de uma chave de texto: `"model":"` → `claude-opus-5-5` (até a próxima aspa sem barra antes)
    static func string(after key: [UInt8], in buf: UnsafeRawBufferPointer) -> String? {
        guard let start = find(key, in: buf).map({ $0 + key.count }) else { return nil }
        var i = start
        var escaped = false
        while i < buf.count {
            let c = buf[i]
            if escaped { escaped = false } else if c == 0x5C { escaped = true } else if c == 0x22 { break }
            i += 1
        }
        guard i < buf.count else { return nil }
        return String(decoding: UnsafeRawBufferPointer(rebasing: buf[start..<i]), as: UTF8.self)
    }

    /// O `}` que fecha o objeto que começa em `start` (o uso não tem chaves dentro de strings)
    static func closingBrace(_ buf: UnsafeRawBufferPointer, from start: Int) -> Int? {
        var depth = 0
        var i = start
        while i < buf.count {
            switch buf[i] {
            case 0x7B: depth += 1
            case 0x7D:
                depth -= 1
                if depth == 0 { return i }
            default: break
            }
            i += 1
        }
        return nil
    }

    /// Chama `body` para cada linha do buffer
    static func lines(_ buf: UnsafeRawBufferPointer, _ body: (UnsafeRawBufferPointer) -> Void) {
        guard let base = buf.baseAddress else { return }
        var start = 0
        while start < buf.count {
            let rest = buf.count - start
            let end: Int
            if let p = memchr(base + start, 0x0A, rest) { end = base.distance(to: UnsafeRawPointer(p)) } else { end = buf.count }
            if end > start { body(UnsafeRawBufferPointer(rebasing: buf[start..<end])) }
            start = end + 1
        }
    }
}

/// Cada linha dos arquivos .jsonl do Claude Code (~/.claude/projects): as respostas do assistente trazem `message.usage`.
/// A mesma resposta pode aparecer em várias linhas (uma por bloco); conta uma vez só, pela id da mensagem e do pedido.
/// As linhas são grandes (o texto, o raciocínio, as ferramentas), mas só interessam uns poucos campos: em vez de
/// decodificar a linha inteira, acha as chaves pelo texto. Dentro de uma string do JSON as aspas vêm escapadas
/// (\"usage\"), então `"usage":{` sem barra antes só pode ser a chave de verdade.
enum ClaudeLog {
    private static let assistant = Array(#""type":"assistant""#.utf8)
    private static let usageKey = Array(#""usage":{"#.utf8)
    private static let modelKey = Array(#""model":""#.utf8)
    private static let idKey = Array(#""id":"msg"#.utf8)
    private static let requestKey = Array(#""requestId":""#.utf8)
    private static let timeKey = Array(#""timestamp":""#.utf8)
    private static let cwdKey = Array(#""cwd":""#.utf8)

    static func parse(_ line: Substring, seen: inout Set<String>) -> UsageRecord? {
        var data = Data(line.utf8)
        return data.withUnsafeMutableBytes { parse(UnsafeRawBufferPointer($0), seen: &seen) }
    }

    static func parse(_ line: UnsafeRawBufferPointer, seen: inout Set<String>) -> UsageRecord? {
        guard line.count > 40, Bytes.find(assistant, in: line) != nil, let u = Bytes.find(usageKey, in: line) else { return nil }
        let model = Bytes.string(after: modelKey, in: line) ?? ""
        // Respostas que o próprio Claude Code inventa (erros, interrupções) não custam nada
        guard !model.isEmpty, model != "<synthetic>" else { return nil }
        let open = u + usageKey.count - 1
        guard let close = Bytes.closingBrace(line, from: open),
              let usage = try? JSONSerialization.jsonObject(with: Data(UnsafeRawBufferPointer(rebasing: line[open...close]))) as? [String: Any] else { return nil }
        let key = "\(Bytes.string(after: idKey, in: line) ?? UUID().uuidString):\(Bytes.string(after: requestKey, in: line) ?? "")"
        guard seen.insert(key).inserted else { return nil }
        guard let date = Bytes.string(after: timeKey, in: line).flatMap(AgentDates.parse) else { return nil }
        var r = UsageRecord(date: date, agent: .claude, model: model, project: AgentDates.project(Bytes.string(after: cwdKey, in: line)))
        r.input = int(usage["input_tokens"])
        r.output = int(usage["output_tokens"])
        r.cacheRead = int(usage["cache_read_input_tokens"])
        if let c = usage["cache_creation"] as? [String: Any] {
            r.cacheWrite5m = int(c["ephemeral_5m_input_tokens"])
            r.cacheWrite1h = int(c["ephemeral_1h_input_tokens"])
        } else {
            r.cacheWrite5m = int(usage["cache_creation_input_tokens"])
        }
        return r.total > 0 ? r : nil
    }

    static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
}

/// As sessões do Codex (~/.codex/sessions/AAAA/MM/DD/*.jsonl). Os eventos `token_count` trazem o total da sessão
/// até ali e os limites do plano (% usada, tamanho da janela e quando zera). O gasto de cada resposta é a diferença
/// entre um total e o anterior, o que evita contar duas vezes um evento repetido.
struct CodexLog {
    var project = "Codex"
    var model = ""
    private var lastTotal = (input: 0, cached: 0, output: 0)
    private(set) var limits: [RateWindow] = []
    private(set) var plan: String?

    private static let markers = [#""session_meta""#, #""turn_context""#, #""token_count""#].map { Array($0.utf8) }

    mutating func parse(_ line: Substring) -> UsageRecord? {
        var data = Data(line.utf8)
        return data.withUnsafeMutableBytes { parse(UnsafeRawBufferPointer($0)) }
    }

    mutating func parse(_ line: UnsafeRawBufferPointer) -> UsageRecord? {
        guard Self.markers.contains(where: { Bytes.find($0, in: line) != nil }) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return nil }
        switch obj["type"] as? String {
        case "session_meta":
            project = AgentDates.project(payload["cwd"] as? String)
            return nil
        case "turn_context":
            if let m = payload["model"] as? String { model = m }
            return nil
        case "event_msg" where payload["type"] as? String == "token_count":
            let date = (obj["timestamp"] as? String).flatMap(AgentDates.parse) ?? Date()
            if let rl = payload["rate_limits"] as? [String: Any] { readLimits(rl, date: date) }
            guard let info = payload["info"] as? [String: Any], let tot = info["total_token_usage"] as? [String: Any] else { return nil }
            let now = (input: ClaudeLog.int(tot["input_tokens"]), cached: ClaudeLog.int(tot["cached_input_tokens"]), output: ClaudeLog.int(tot["output_tokens"]))
            // O total só cresce numa sessão; se voltou (sessão retomada do zero), começa de novo
            let base = now.input >= lastTotal.input && now.output >= lastTotal.output ? lastTotal : (input: 0, cached: 0, output: 0)
            lastTotal = now
            let dIn = now.input - base.input, dCached = now.cached - base.cached, dOut = now.output - base.output
            guard dIn + dOut > 0 else { return nil }
            var r = UsageRecord(date: date, agent: .codex, model: model.isEmpty ? "codex" : model, project: project)
            // Na OpenAI, a entrada inclui a parte que veio do cache
            r.cacheRead = max(0, dCached)
            r.input = max(0, dIn - dCached)
            r.output = dOut
            return r
        default:
            return nil
        }
    }

    private mutating func readLimits(_ rl: [String: Any], date: Date) {
        var out: [RateWindow] = []
        for k in ["primary", "secondary"] {
            guard let w = rl[k] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let mins = (w["window_minutes"] as? NSNumber)?.intValue
            let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            out.append(RateWindow(label: RateWindow.label(minutes: mins), usedPercent: used, resetsAt: reset, windowMinutes: mins, asOf: date))
        }
        if !out.isEmpty { limits = out }
        if let p = rl["plan_type"] as? String, !p.isEmpty { plan = p.capitalized }
    }
}

/// O Gemini CLI grava cada conversa num arquivo JSON (~/.gemini/tmp/<projeto>/chats/session-*.json);
/// as respostas (`type: "gemini"`) trazem `tokens` e o modelo
enum GeminiLog {
    static func parse(_ data: Data, project: String) -> [UsageRecord] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = obj["messages"] as? [[String: Any]] else { return [] }
        return messages.compactMap { m in
            guard m["type"] as? String == "gemini", let t = m["tokens"] as? [String: Any],
                  let date = (m["timestamp"] as? String).flatMap(AgentDates.parse) else { return nil }
            var r = UsageRecord(date: date, agent: .gemini, model: m["model"] as? String ?? "gemini", project: project)
            let input = ClaudeLog.int(t["input"]), cached = ClaudeLog.int(t["cached"])
            r.cacheRead = cached
            r.input = max(0, input - cached)
            r.output = ClaudeLog.int(t["output"]) + ClaudeLog.int(t["thoughts"])
            return r.total > 0 ? r : nil
        }
    }
}

enum AgentDates {
    nonisolated(unsafe) private static let frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()
    private static let lock = NSLock()

    static func parse(_ s: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return frac.date(from: s) ?? plain.date(from: s)
    }

    /// "/Users/ana/apps/menew" → "menew"
    static func project(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "—" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}

// MARK: Preços

/// Custo estimado pelos preços públicos da API da Anthropic (US$ por milhão de tokens). Num plano Pro ou Max você
/// não paga isso; serve para ver o tamanho do uso. Escrever no cache custa 1,25× a entrada (5 min) ou 2× (1 hora).
enum AgentPricing {
    struct Price { let input: Double, output: Double, cacheRead: Double }

    /// Do mais específico para o mais geral: "opus-5-5" antes de "opus-5"
    static let table: [(String, Price)] = [
        ("fable-5-2", Price(input: 8, output: 40, cacheRead: 0.2)),
        ("mythos-5-2", Price(input: 8, output: 40, cacheRead: 0.2)),
        ("fable-5", Price(input: 10, output: 50, cacheRead: 1)),
        ("mythos-5", Price(input: 10, output: 50, cacheRead: 1)),
        ("opus-5-5", Price(input: 4, output: 20, cacheRead: 0.2)),
        ("opus-5", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4-8", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4-7", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4-6", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4-5", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4", Price(input: 15, output: 75, cacheRead: 1.5)),
        ("sonnet-5-5", Price(input: 2, output: 10, cacheRead: 0.1)),
        ("sonnet-5", Price(input: 2, output: 10, cacheRead: 0.2)),
        ("sonnet-4", Price(input: 3, output: 15, cacheRead: 0.3)),
        ("haiku-5-5", Price(input: 0.1, output: 0.5, cacheRead: 0.01)),
        ("haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.1)),
        ("haiku", Price(input: 0.8, output: 4, cacheRead: 0.08)),
    ]

    static func price(_ model: String) -> Price? {
        let m = model.lowercased()
        return table.first { m.contains($0.0) }?.1
    }

    /// nil para modelos sem preço conhecido (Codex e Gemini: o plano é por assinatura)
    static func cost(_ r: UsageRecord) -> Double? {
        guard r.agent == .claude, let p = price(r.model) else { return nil }
        let perM = 1_000_000.0
        return (Double(r.input) * p.input + Double(r.output) * p.output + Double(r.cacheRead) * p.cacheRead
                + Double(r.cacheWrite5m) * p.input * 1.25 + Double(r.cacheWrite1h) * p.input * 2) / perM
    }

    /// Quanto o cache economizou: o que a leitura do cache custaria como entrada normal, menos o que custou
    static func cacheSavings(_ r: UsageRecord) -> Double {
        guard r.agent == .claude, let p = price(r.model) else { return 0 }
        return Double(r.cacheRead) * (p.input - p.cacheRead) / 1_000_000
    }

    /// "claude-opus-5-5-20260101" → "Opus 5.5"; os outros ficam como vieram
    static func displayName(_ model: String) -> String {
        let m = model.lowercased()
        for family in ["fable", "mythos", "opus", "sonnet", "haiku"] {
            guard let r = m.range(of: family + "-") else { continue }
            let nums = m[r.upperBound...].split(separator: "-").prefix(2).filter { $0.count <= 2 && Int($0) != nil }
            return family.capitalized + (nums.isEmpty ? "" : " " + nums.joined(separator: "."))
        }
        return model
    }
}

// MARK: Leitura incremental

/// Lê só o que foi acrescentado desde a última vez em cada arquivo, numa fila própria.
/// Os registros dos últimos 31 dias ficam na memória (um registro por resposta, coisa de poucos MB).
final class AgentUsageScanner: @unchecked Sendable {
    static let days = 31

    private struct FileState {
        var offset: UInt64 = 0
        var carry = Data()
        var seen = Set<String>()
        var codex = CodexLog()
        var records: [UsageRecord] = []
        var mtime = Date.distantPast
    }

    private var files: [String: FileState] = [:]
    private let queue = DispatchQueue(label: "menew.agent-usage", qos: .utility)

    struct Result {
        var records: [UsageRecord]
        var codexLimits: [RateWindow]
        var codexPlan: String?
    }

    func scan(_ done: @escaping @Sendable (Result) -> Void) {
        queue.async { [self] in done(scanNow()) }
    }

    /// Síncrono (o servidor MCP usa direto)
    func scanNow() -> Result {
        let cutoff = Date().addingTimeInterval(-Double(Self.days) * 86400)
        var alive = Set<String>()
        var codexLatest: (Date, [RateWindow], String?)?

        for url in Self.jsonl(under: AgentKind.claude.home.appendingPathComponent("projects"), cutoff: cutoff) {
            alive.insert(url.path)
            update(url, agent: .claude)
        }
        for url in Self.jsonl(under: AgentKind.codex.home.appendingPathComponent("sessions"), cutoff: cutoff) {
            alive.insert(url.path)
            update(url, agent: .codex)
            if let st = files[url.path], !st.codex.limits.isEmpty, let asOf = st.codex.limits.first?.asOf,
               asOf > (codexLatest?.0 ?? .distantPast) {
                codexLatest = (asOf, st.codex.limits, st.codex.plan)
            }
        }
        for url in Self.geminiChats(cutoff: cutoff) {
            alive.insert(url.path)
            updateWhole(url)
        }
        files = files.filter { alive.contains($0.key) }
        let records = files.values.flatMap { $0.records.filter { $0.date >= cutoff } }.sorted { $0.date < $1.date }
        return Result(records: records, codexLimits: codexLatest?.1 ?? [], codexPlan: codexLatest?.2)
    }

    private func update(_ url: URL, agent: AgentKind) {
        var st = files[url.path] ?? FileState()
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64 else { return }
        if size < st.offset { st = FileState() }   // reescrito do zero
        guard size > st.offset, let h = try? FileHandle(forReadingFrom: url) else { files[url.path] = st; return }
        defer { try? h.close() }
        try? h.seek(toOffset: st.offset)
        // Em pedaços de 8 MB, para um arquivo enorme não ocupar a memória de uma vez
        // Cada pedaço lido (e os objetos do JSON) sai da memória antes do próximo
        var more = true
        while more {
            more = autoreleasepool { () -> Bool in
                guard let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
                st.offset += UInt64(chunk.count)
                var buf = st.carry + chunk
                guard let lastNL = buf.lastIndex(of: 0x0A) else { st.carry = buf; return true }
                st.carry = buf[(lastNL + 1)...].isEmpty ? Data() : Data(buf[(lastNL + 1)...])
                buf = buf[..<lastNL]
                buf.withUnsafeBytes { raw in
                    Bytes.lines(raw) { line in
                        switch agent {
                        case .claude: if let r = ClaudeLog.parse(line, seen: &st.seen) { st.records.append(r) }
                        case .codex: if let r = st.codex.parse(line) { st.records.append(r) }
                        case .gemini: break
                        }
                    }
                }
                return true
            }
        }
        files[url.path] = st
    }

    /// O Gemini reescreve o arquivo inteiro a cada mensagem: lê de novo quando muda
    private func updateWhole(_ url: URL) {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        if let st = files[url.path], st.mtime >= mtime { return }
        var st = FileState()
        st.mtime = mtime
        if let data = try? Data(contentsOf: url) {
            // tmp/<hash do projeto>/chats/arquivo.json: o nome da pasta não diz qual projeto, só "Gemini"
            st.records = GeminiLog.parse(data, project: "Gemini")
        }
        files[url.path] = st
    }

    static func jsonl(under dir: URL, cutoff: Date) -> [URL] {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if mtime >= cutoff { out.append(url) }
        }
        return out
    }

    static func geminiChats(cutoff: Date) -> [URL] {
        let tmp = AgentKind.gemini.home.appendingPathComponent("tmp")
        guard let projects = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return [] }
        return projects.flatMap { p -> [URL] in
            let chats = p.appendingPathComponent("chats")
            let files = (try? FileManager.default.contentsOfDirectory(at: chats, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return files.filter {
                $0.pathExtension == "json" &&
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) >= cutoff
            }
        }
    }
}

// MARK: Limites do plano do Claude (opcional, pela internet)

/// A % das janelas de 5 horas e da semana só a Anthropic sabe. Quando você liga, o Menew lê o login do Claude Code
/// (o macOS pergunta antes de liberar as Chaves) e consulta o mesmo endereço que a tela de uso do Claude usa.
/// Não é uma API documentada: se mudar, o Menew mostra só o que lê no Mac.
enum ClaudePlanLimits {
    static let key = "agents.claudePlan"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    enum Failure: Error { case noLogin, expired, network, format }

    struct Credentials { let token: String; let expires: Date?; let plan: String? }

    static func credentials() -> Credentials? {
        var data: Data?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials",
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess { data = out as? Data }
        if data == nil { data = try? Data(contentsOf: AgentKind.claude.home.appendingPathComponent(".credentials.json")) }
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String else { return nil }
        let exp = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(token: token, expires: exp, plan: (oauth["subscriptionType"] as? String)?.capitalized)
    }

    static func fetch() async -> Swift.Result<(plan: String?, windows: [RateWindow]), Failure> {
        guard let c = await Task.detached(operation: { credentials() }).value else { return .failure(.noLogin) }
        // O token não é renovado aqui (isso é com o Claude Code): vencido, é só abrir o Claude Code de novo
        if let exp = c.expires, exp < Date() { return .failure(.expired) }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        req.setValue("Bearer \(c.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("Menew", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return .failure(.network) }
        if (resp as? HTTPURLResponse)?.statusCode == 401 { return .failure(.expired) }
        guard let windows = parse(data) else { return .failure(.format) }
        return .success((c.plan, windows))
    }

    /// {"five_hour": {"utilization": 12, "resets_at": "…"}, "seven_day": {…}, "seven_day_opus": null, …}
    static func parse(_ data: Data, now: Date = Date()) -> [RateWindow]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let known: [(String, Int?)] = [("five_hour", 300), ("seven_day", 10080)]
        var out: [RateWindow] = []
        for (k, v) in obj.sorted(by: { order($0.key) < order($1.key) }) {
            guard let w = v as? [String: Any], let used = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
            let mins = known.first { $0.0 == k }?.1 ?? (k.hasPrefix("seven_day") ? 10080 : (k.hasPrefix("five_hour") ? 300 : nil))
            var label = RateWindow.label(minutes: mins)
            // seven_day_opus → "Semana · Opus"
            for prefix in ["seven_day_", "five_hour_"] where k.hasPrefix(prefix) {
                label += " · " + k.dropFirst(prefix.count).split(separator: "_").map { $0.capitalized }.joined(separator: " ")
            }
            out.append(RateWindow(label: label, usedPercent: used, resetsAt: (w["resets_at"] as? String).flatMap(AgentDates.parse),
                                  windowMinutes: mins, asOf: now))
        }
        return out
    }

    private static func order(_ k: String) -> String { (k == "five_hour" ? "0" : k == "seven_day" ? "1" : "2") + k }
}

// MARK: Modelos rodando no Mac

/// Ollama e LM Studio: quais modelos estão carregados e quanta memória ocupam. Só endereços locais (127.0.0.1).
struct LocalModel: Identifiable, Equatable {
    var id: String { app + name }
    var app: String
    var name: String
    var bytes: Int64?
}

enum LocalModels {
    static func fetch() async -> [LocalModel] {
        async let ollama = ollamaModels()
        async let lms = lmStudioModels()
        return await ollama + lms
    }

    private static func json(_ url: String) async -> [String: Any]? {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 1.5)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func ollamaModels() async -> [LocalModel] {
        guard let obj = await json("http://127.0.0.1:11434/api/ps") else { return [] }
        return parseOllama(obj)
    }

    static func parseOllama(_ obj: [String: Any]) -> [LocalModel] {
        ((obj["models"] as? [[String: Any]]) ?? []).compactMap { m in
            guard let name = m["name"] as? String else { return nil }
            return LocalModel(app: "Ollama", name: name, bytes: (m["size"] as? NSNumber)?.int64Value)
        }
    }

    static func lmStudioModels() async -> [LocalModel] {
        guard let obj = await json("http://127.0.0.1:1234/api/v0/models") else { return [] }
        return ((obj["data"] as? [[String: Any]]) ?? []).compactMap { m in
            guard m["state"] as? String == "loaded", let id = m["id"] as? String else { return nil }
            return LocalModel(app: "LM Studio", name: id, bytes: nil)
        }
    }
}

// MARK: Estado

@MainActor
final class AgentUsageStore: ObservableObject {
    static let shared = AgentUsageStore()
    static let alertsKey = "agents.limitAlerts"

    @Published private(set) var records: [UsageRecord] = []
    @Published private(set) var limits: [AgentKind: [RateWindow]] = [:]
    @Published private(set) var plans: [AgentKind: String] = [:]
    @Published private(set) var claudeLimitError: ClaudePlanLimits.Failure?
    @Published private(set) var localModels: [LocalModel] = []
    @Published private(set) var lastScan: Date?
    @Published private(set) var scanning = false

    private let scanner = AgentUsageScanner()
    private var timer: Timer?
    private var lastClaudeFetch = Date.distantPast
    private var demo = false
    /// A seção está aberta: os modelos locais são consultados só enquanto isso
    var isVisible = false { didSet { if isVisible { refresh() } } }

    var installed: [AgentKind] { AgentKind.allCases.filter { a in a.isInstalled || records.contains { $0.agent == a } } }

    func start() {
        guard timer == nil else { return }
        refresh()
        // A cada 2 minutos: barato (só lê o que foi acrescentado) e deixa os avisos de limite em dia
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            MainActor.assumeIsolated { AgentUsageStore.shared.refresh() }
        }
        timer?.tolerance = 20
    }

    func refresh() {
        guard !demo, !scanning else { return }
        guard AgentKind.allCases.contains(where: \.isInstalled) else { return }
        scanning = true
        scanner.scan { result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let s = AgentUsageStore.shared
                    s.records = result.records
                    if !result.codexLimits.isEmpty { s.limits[.codex] = result.codexLimits }
                    if let p = result.codexPlan { s.plans[.codex] = p }
                    s.lastScan = Date()
                    s.scanning = false
                    s.checkAlerts()
                }
            }
        }
        if ClaudePlanLimits.isOn, Date().timeIntervalSince(lastClaudeFetch) > 280 {
            lastClaudeFetch = Date()
            Task {
                switch await ClaudePlanLimits.fetch() {
                case .success(let r):
                    limits[.claude] = r.windows
                    if let p = r.plan { plans[.claude] = p }
                    claudeLimitError = nil
                    checkAlerts()
                case .failure(let f):
                    claudeLimitError = f
                }
            }
        } else if !ClaudePlanLimits.isOn {
            limits[.claude] = nil
            claudeLimitError = nil
        }
        if isVisible { Task { localModels = await LocalModels.fetch() } }
    }

    func setClaudePlan(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: ClaudePlanLimits.key)
        lastClaudeFetch = .distantPast
        refresh()
    }

    // MARK: Contas

    struct Totals { var tokens = 0; var cost = 0.0; var savings = 0.0; var replies = 0 }

    func totals(since: Date, agent: AgentKind? = nil) -> Totals {
        var t = Totals()
        for r in records where r.date >= since && (agent == nil || r.agent == agent) {
            t.tokens += r.total
            t.cost += AgentPricing.cost(r) ?? 0
            t.savings += AgentPricing.cacheSavings(r)
            t.replies += 1
        }
        return t
    }

    /// Tokens por dia nos últimos `days` dias, de cada ferramenta (para o gráfico)
    func daily(days: Int) -> [(day: Date, agent: AgentKind, tokens: Int)] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date()))!
        var buckets: [Date: [AgentKind: Int]] = [:]
        for r in records where r.date >= start {
            buckets[cal.startOfDay(for: r.date), default: [:]][r.agent, default: 0] += r.total
        }
        return (0..<days).flatMap { i -> [(Date, AgentKind, Int)] in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            return AgentKind.allCases.map { (d, $0, buckets[d]?[$0] ?? 0) }
        }
    }

    /// Os maiores (por tokens) numa dimensão: modelo ou projeto
    func top(since: Date, by key: (UsageRecord) -> String, limit: Int = 5) -> [(name: String, agent: AgentKind, tokens: Int, cost: Double)] {
        var acc: [String: (AgentKind, Int, Double)] = [:]
        for r in records where r.date >= since {
            let k = key(r)
            let cur = acc[k] ?? (r.agent, 0, 0)
            acc[k] = (cur.0, cur.1 + r.total, cur.2 + (AgentPricing.cost(r) ?? 0))
        }
        return acc.sorted { $0.value.1 > $1.value.1 }.prefix(limit).map { ($0.key, $0.value.0, $0.value.1, $0.value.2) }
    }

    /// Tokens por minuto nos últimos 5 minutos: dá a ideia de quem está trabalhando agora
    func burnRate(_ agent: AgentKind, now: Date = Date()) -> Int {
        records.filter { $0.agent == agent && $0.date > now.addingTimeInterval(-300) }.reduce(0) { $0 + $1.output } / 5
    }

    // MARK: Avisos

    /// 75% e 90% de cada janela, uma vez por janela (pelo horário do reset)
    private func checkAlerts() {
        guard UserDefaults.standard.object(forKey: Self.alertsKey) as? Bool ?? true else { return }
        var fired = Set(UserDefaults.standard.stringArray(forKey: "agents.alertsFired") ?? [])
        for (agent, windows) in limits {
            for w in windows {
                for threshold in [90.0, 75.0] where w.usedPercent >= threshold {
                    let id = "\(agent.rawValue).\(w.label).\(Int(w.resetsAt?.timeIntervalSince1970 ?? 0)).\(Int(threshold))"
                    guard !fired.contains(id) else { break }
                    fired.insert(id)
                    let reset = w.resetsAt.map { L("Zera %@.", $0.formatted(.relative(presentation: .named).locale(L10n.locale))) } ?? ""
                    Alerts.shared.notify(id: "menew.agent.\(id)", title: L("%@: %d%% do limite (%@)", agent.name, Int(w.usedPercent), w.label), body: reset)
                    break
                }
            }
        }
        UserDefaults.standard.set(Array(fired.suffix(200)), forKey: "agents.alertsFired")
    }

    // MARK: Capturas de tela

    func showDemo() {
        demo = true
        let now = Date()
        var out: [UsageRecord] = []
        var rng = SystemRandomNumberGenerator()
        let projects = ["menew", "api", "site", "mobile"]
        for d in 0..<30 {
            let n = Int.random(in: 6...22, using: &rng)
            for i in 0..<n {
                let date = now.addingTimeInterval(-Double(d) * 86400 - Double(i) * 900)
                var r = UsageRecord(date: date, agent: i % 4 == 3 ? .codex : .claude, model: i % 4 == 3 ? "gpt-5.5-codex" : (i % 3 == 0 ? "claude-sonnet-5-5" : "claude-opus-5-5"),
                                    project: projects[(i + d) % projects.count])
                r.input = Int.random(in: 20...600, using: &rng)
                r.output = Int.random(in: 300...4000, using: &rng)
                r.cacheRead = Int.random(in: 20_000...90_000, using: &rng)
                r.cacheWrite1h = Int.random(in: 0...6_000, using: &rng)
                out.append(r)
            }
            if d % 3 == 0 {
                var g = UsageRecord(date: now.addingTimeInterval(-Double(d) * 86400 - 5000), agent: .gemini, model: "gemini-3-pro", project: "Gemini")
                g.input = 40_000; g.output = 3_000
                out.append(g)
            }
        }
        records = out.sorted { $0.date < $1.date }
        limits = [
            .claude: [RateWindow(label: L("5 horas"), usedPercent: 62, resetsAt: now.addingTimeInterval(5400), windowMinutes: 300, asOf: now),
                      RateWindow(label: L("Semana"), usedPercent: 38, resetsAt: now.addingTimeInterval(3 * 86400), windowMinutes: 10080, asOf: now)],
            .codex: [RateWindow(label: L("5 horas"), usedPercent: 21, resetsAt: now.addingTimeInterval(9000), windowMinutes: 300, asOf: now),
                     RateWindow(label: L("Semana"), usedPercent: 9, resetsAt: now.addingTimeInterval(5 * 86400), windowMinutes: 10080, asOf: now)],
        ]
        plans = [.claude: "Max", .codex: "Plus"]
        localModels = [LocalModel(app: "Ollama", name: "qwen3-coder:30b", bytes: 19_400_000_000)]
        lastScan = now
    }
}
