import AppKit
import Combine
import CryptoKit
import SwiftUI

/// Memória automática: fontes que alimentam a Memória sozinhas, cada uma com o seu interruptor (todas desligadas por
/// padrão). Prints de qualquer app (copiados ou salvos) e um resumo de cada sessão do Claude Code, Codex e Gemini CLI.
/// Tudo lido no Mac, sem internet; segredos (itens ocultos, apps de senhas, chaves e tokens) ficam de fora.
enum MemoryFeed {
    enum Source: String, CaseIterable, Identifiable {
        case screenshots, recordings, notes, claude, codex, gemini
        var id: String { rawValue }

        var key: String { "memory.auto.\(rawValue)" }
        var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

        var title: String {
            switch self {
            case .screenshots: L("Todos os prints")
            case .recordings: L("Atas das gravações")
            case .notes: L("Notas")
            case .claude: L("Sessões do Claude Code")
            case .codex: L("Sessões do Codex")
            case .gemini: L("Sessões do Gemini CLI")
            }
        }

        var detail: String {
            switch self {
            case .screenshots: L("Prints copiados ou salvos de qualquer app (⌘⇧4, ⌘⇧5, CleanShot…), com o texto lido no Mac.")
            case .recordings: L("Cada reunião gravada: assunto, resumo, decisões, tarefas e próximos passos. A transcrição inteira fica de fora.")
            case .notes: L("Suas notas, atualizadas quando você edita. Notas protegidas e de senhas nunca entram; protegeu ou apagou, sai da Memória.")
            case .claude, .codex, .gemini: L("Um resumo por sessão: projeto, pedido, o que foi feito e os arquivos mexidos. Chaves e tokens ficam de fora.")
            }
        }

        var icon: String {
            switch self {
            case .screenshots: "camera.viewfinder"
            case .recordings: "waveform"
            case .notes: "note.text"
            case .claude: AgentKind.claude.icon
            case .codex: AgentKind.codex.icon
            case .gemini: AgentKind.gemini.icon
            }
        }

        var agent: AgentKind? {
            switch self {
            case .screenshots, .recordings, .notes: nil
            case .claude: .claude
            case .codex: .codex
            case .gemini: .gemini
            }
        }
    }

    /// Quanto do passado entra quando uma fonte é ligada
    static let backfillDays = 30

    /// Apps de senhas: um print tirado com eles na frente não vai para a Memória
    static let passwordApps: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "in.sinew.Enpass-Desktop", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal",
    ]

    @MainActor static func start() {
        ScreenshotFeed.shared.refresh()
        AgentSessionFeed.shared.refresh()
        MirrorFeed.shared.refresh()
    }

    @MainActor static func set(_ source: Source, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: source.key)
        switch source {
        case .screenshots: ScreenshotFeed.shared.refresh()
        case .recordings, .notes: MirrorFeed.shared.refresh()
        case .claude, .codex, .gemini: AgentSessionFeed.shared.refresh()
        }
    }

    static func binding(_ source: Source) -> Binding<Bool> {
        Binding(get: { source.isOn }, set: { on in MainActor.assumeIsolated { set(source, on) } })
    }

    // MARK: Prints copiados

    /// Um print copiado tem só tipos de imagem; uma imagem copiada de uma página vem com HTML, link ou texto junto
    static func looksLikeScreenshot(types: [String]) -> Bool {
        let image = ["public.png", "public.tiff", "public.jpeg", "public.heic", "NSTIFFPboardType", "Apple PNG pasteboard type"]
        let notShot = ["public.html", "public.url", "public.file-url", "public.utf8-plain-text", "public.rtf", "com.apple.webarchive",
                       "Apple URL pasteboard type", "NSStringPboardType", "Apple HTML pasteboard type", "com.apple.flat-rtfd"]
        return types.contains(where: image.contains) && !types.contains(where: notShot.contains)
    }

    /// Chamado pelo clipboard quando uma imagem nova é copiada
    @MainActor static func clipboardImage(_ file: URL, types: [String], concealed: Bool, app: String?, bundle: String?) {
        guard Source.screenshots.isOn, !concealed, looksLikeScreenshot(types: types),
              !(bundle.map(passwordApps.contains) ?? false), let data = try? Data(contentsOf: file) else { return }
        let key = ImageFingerprint.key(data)
        guard let key, !MemoryStore.shared.has(sourceKey: key) else { return }
        var origin = MemoryOrigin.current()
        if origin.app == nil { origin.app = app; origin.bundle = bundle }
        MemoryStore.shared.add(imageData: data, origin: origin, sourceKey: key, auto: true)
    }
}

// MARK: Segredos

/// Tira de um texto o que parece segredo: chaves de API, tokens, senhas em `chave=valor`, chaves privadas
enum SecretScrubber {
    static let mask = "[•••]"

    private static let patterns: [NSRegularExpression] = [
        // Chaves privadas inteiras
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
        // Prefixos conhecidos: Anthropic, OpenAI, GitHub, Slack, Google, AWS, Stripe, npm, GitLab, Hugging Face
        #"\b(sk-ant-[A-Za-z0-9_\-]{10,}|sk-(proj-)?[A-Za-z0-9_\-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abposr]-[A-Za-z0-9\-]{10,}|AIza[0-9A-Za-z_\-]{30,}|AKIA[0-9A-Z]{16}|[rs]k_(live|test)_[0-9A-Za-z]{16,}|npm_[A-Za-z0-9]{30,}|glpat-[A-Za-z0-9_\-]{20,}|hf_[A-Za-z0-9]{30,})\b"#,
        // JWT
        #"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#,
        // Authorization: Bearer xxx
        #"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=\-]{16,}"#,
        // Senha em URL: https://user:senha@host
        #"(?<=://)[^/\s:@]+:[^/\s@]+(?=@)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// api_key=…, "token": "…", PASSWORD: … (o nome fica, o valor some)
    private static let assignment = try? NSRegularExpression(
        pattern: #"(?i)(["']?[A-Za-z0-9_\-]*(api[_\-]?key|secret|token|passw(or)?d|senha|credential|private[_\-]?key|access[_\-]?key)[A-Za-z0-9_\-]*["']?\s*[:=]\s*)(["']?)[^\s"',;}]{6,}\4"#)

    static func scrub(_ s: String) -> String {
        var out = s
        for re in patterns {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: mask)
        }
        if let assignment {
            out = assignment.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1$4\(mask)$4")
        }
        return out
    }
}

// MARK: Impressão digital de imagem

/// A mesma imagem em PNG ou TIFF (clipboard e arquivo) dá a mesma chave: compara os pixels reduzidos, não os bytes
enum ImageFingerprint {
    static func key(_ data: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return key(cg)
    }

    static func key(_ cg: CGImage) -> String? {
        let side = 24
        var px = [UInt8](repeating: 0, count: side * side)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        // Quantizado para engolir diferenças mínimas de cor entre formatos
        let q = px.map { $0 >> 3 }
        let hash = SHA256.hash(data: Data(q) + Data("\(cg.width)x\(cg.height)".utf8))
        return "shot:" + hash.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: Prints salvos

/// Prints salvos em arquivo, de qualquer pasta: o Spotlight marca os do macOS (⌘⇧3/4/5) como captura de tela, e os
/// nomes dos apps de captura mais usados (CleanShot, Shottr) entram também. Só os novos; os de antes entram até 30 dias.
@MainActor
final class ScreenshotFeed: NSObject {
    static let shared = ScreenshotFeed()
    private var query: NSMetadataQuery?
    private var seen = Set<String>()
    private static let seenKey = "memory.auto.screenshots.seen"
    private static let maxBackfill = 60

    func refresh() {
        guard MemoryFeed.Source.screenshots.isOn else { stop(); return }
        guard query == nil else { return }
        seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        let since = Date().addingTimeInterval(-Double(MemoryFeed.backfillDays) * 86400)
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.predicate = NSPredicate(format: "(kMDItemIsScreenCapture == 1 OR kMDItemFSName LIKE[c] 'CleanShot*' OR kMDItemFSName LIKE[c] 'Shottr*') AND kMDItemContentTypeTree == 'public.image' AND kMDItemContentCreationDate >= %@", since as NSDate)
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .NSMetadataQueryDidUpdate, object: q)
        query = q
        q.start()
    }

    private func stop() {
        guard let q = query else { return }
        q.stop()
        NotificationCenter.default.removeObserver(self, name: nil, object: q)
        query = nil
    }

    @objc private func changed(_ note: Notification) {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        var fresh: [(URL, Date)] = []
        for case let item as NSMetadataItem in q.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String, !seen.contains(path) else { continue }
            let date = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? Date()
            fresh.append((URL(fileURLWithPath: path), date))
        }
        guard !fresh.isEmpty else { return }
        // Os mais novos primeiro; no primeiro passeio, um limite para não encher a memória de uma vez
        let recent = Date().addingTimeInterval(-120)
        let isLive = fresh.allSatisfy { $0.1 > recent }
        let batch = fresh.prefix(isLive ? fresh.count : Self.maxBackfill)
        for (url, date) in batch where add(url, date: date, live: date > recent) {
            seen.insert(url.path)
        }
        // Os que ficaram de fora do limite também contam como vistos (os que não deu para ler, não: tentam de novo)
        for (url, _) in fresh.dropFirst(batch.count) { seen.insert(url.path) }
        UserDefaults.standard.set(Array(seen.suffix(2000)), forKey: Self.seenKey)
    }

    /// false: não deu para ler agora (sem acesso à pasta ainda, arquivo pela metade); fica para a próxima
    @discardableResult
    private func add(_ url: URL, date: Date, live: Bool) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return !FileManager.default.fileExists(atPath: url.path) }
        guard let key = ImageFingerprint.key(data) else { return false }
        if MemoryStore.shared.has(sourceKey: key) { return true }
        // Um print de agora vem do app da frente; um antigo, só do nome do arquivo
        var origin = MemoryOrigin()
        if live {
            origin = MemoryOrigin.current()
            if let b = origin.bundle, MemoryFeed.passwordApps.contains(b) { return true }
        }
        if origin.window == nil { origin.window = url.deletingPathExtension().lastPathComponent }
        MemoryStore.shared.add(imageData: data, origin: origin, sourceKey: key, auto: true, date: date)
        return true
    }
}

// MARK: Atas e notas

/// Um item espelhado de outra parte do Menew (gravação, nota): o que vai para a Memória, já sem segredos
struct MirrorEntry: Equatable {
    var sourceKey: String
    var kind: MemoryItem.Kind
    var title: String
    var summary = ""
    var text: String
    var app: String
    var date: Date
    var tags: [String] = []
    var entities: [String] = []

    func apply(to item: inout MemoryItem) {
        item.kind = kind
        item.title = title
        item.summary = summary
        item.text = text
        item.app = app
        item.date = date
        item.tags = tags
        item.entities = entities
        item.sourceKey = sourceKey
        // Já vem organizado (a ata pela IA, a nota por você): a IA não renomeia
        item.enriched = true
    }

    /// Uma gravação pronta vira a ata em texto: assunto, resumo, tópicos, decisões, tarefas e próximos passos
    static func recording(_ r: Recording) -> MirrorEntry? {
        guard r.status == .ready else { return nil }
        let empty = L("Nenhuma fala reconhecida.")
        guard !(r.summary.isEmpty || r.summary == empty) || !r.decisions.isEmpty || !r.tasks.isEmpty else { return nil }
        var lines: [String] = []
        if let t = r.theme, !t.isEmpty { lines.append(t) }
        if !r.summary.isEmpty { lines.append(r.summary) }
        for t in r.topics ?? [] { lines.append("## \(t.title)\n" + t.points.map { "- \($0)" }.joined(separator: "\n")) }
        if !r.decisions.isEmpty { lines.append("\(L("Decisões")):\n" + r.decisions.map { "- \($0)" }.joined(separator: "\n")) }
        if !r.tasks.isEmpty {
            lines.append("\(L("Tarefas")):\n" + r.tasks.map { t in
                "- \(t.text)" + (t.owner.map { " (\($0))" } ?? "") + (t.due.map { " · \($0)" } ?? "")
            }.joined(separator: "\n"))
        }
        if let n = r.nextSteps, !n.isEmpty { lines.append("\(L("Próximos passos")):\n" + n.map { "- \($0)" }.joined(separator: "\n")) }
        if !r.people.isEmpty { lines.append("\(L("Pessoas")): " + r.people.joined(separator: ", ")) }
        return MirrorEntry(sourceKey: "recording:\(r.id.uuidString)", kind: .recording, title: SecretScrubber.scrub(r.title),
                           summary: SecretScrubber.scrub(AgentSessionDigest.clip(r.summary, 200)),
                           text: SecretScrubber.scrub(lines.joined(separator: "\n\n")), app: L("Gravações"), date: r.date,
                           tags: r.tags, entities: r.people)
    }

    /// Uma nota de texto com conteúdo. Protegidas e de senhas nunca; a ata de uma gravação já entra como gravação.
    static func note(_ n: Note, skip: Set<UUID> = []) -> MirrorEntry? {
        guard !n.secure, !n.isPasswords, !skip.contains(n.id) else { return nil }
        let body = n.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count >= 12 else { return nil }
        let text = SecretScrubber.scrub(String(body.prefix(6000)))
        return MirrorEntry(sourceKey: "note:\(n.id.uuidString)", kind: .note, title: SecretScrubber.scrub(n.title),
                           summary: SecretScrubber.scrub(n.preview), text: text, app: L("Notas"), date: n.updated, tags: n.tags)
    }
}

/// Atas das gravações e notas na Memória: acompanha as duas listas e espelha (com uma pausa, para não regravar a cada tecla)
@MainActor
final class MirrorFeed {
    static let shared = MirrorFeed()
    private var subs: [AnyCancellable] = []

    func refresh() {
        subs = []
        let recOn = MemoryFeed.Source.recordings.isOn, notesOn = MemoryFeed.Source.notes.isOn
        guard recOn || notesOn else { return }
        let recordings = RecordingStore.shared
        if recOn {
            recordings.$items
                .debounce(for: .seconds(2), scheduler: RunLoop.main)
                .sink { list in MainActor.assumeIsolated { MemoryStore.shared.sync(prefix: "recording:", list.compactMap(MirrorEntry.recording)) } }
                .store(in: &subs)
        }
        if notesOn, let store = (NSApp.delegate as? AppDelegate)?.notes {
            store.$notes
                .debounce(for: .seconds(5), scheduler: RunLoop.main)
                .sink { list in
                    MainActor.assumeIsolated {
                        let fromRecordings = Set(RecordingStore.shared.items.compactMap(\.noteID))
                        MemoryStore.shared.sync(prefix: "note:", list.compactMap { MirrorEntry.note($0, skip: fromRecordings) })
                    }
                }
                .store(in: &subs)
        }
    }
}

// MARK: Sessões dos agentes

/// O resumo de uma sessão de agente, montado linha a linha: o projeto, o pedido, a última resposta, os arquivos e comandos
struct AgentSessionDigest: Equatable {
    var agent: AgentKind
    var sessionID = ""
    var cwd: String?
    var branch: String?
    var aiTitle: String?
    var prompts: [String] = []
    var lastReply: String?
    var files: [String] = []
    var commands: [String] = []
    var steps = 0
    var start: Date?
    var end: Date?

    init(agent: AgentKind) { self.agent = agent }

    var sourceKey: String { "\(agent.rawValue):\(sessionID)" }
    var project: String { cwd.map { AgentDates.project($0) } ?? agent.short }

    /// Uma sessão só com o pedido e nenhuma resposta (ou aberta e fechada) não vale um item
    var isWorthKeeping: Bool { !sessionID.isEmpty && !prompts.isEmpty && (lastReply != nil || steps > 0) }

    var title: String {
        let t = aiTitle ?? prompts.first.flatMap(AgentStep.task) ?? agent.name
        return SecretScrubber.scrub(String(t.prefix(90)))
    }

    /// O texto guardado na Memória (e lido pela busca e pela IA)
    var text: String {
        var lines: [String] = []
        lines.append("\(L("Projeto")): \(project)" + (branch.map { " (\($0))" } ?? "") + (cwd.map { " · \($0)" } ?? ""))
        if let first = prompts.first { lines.append("\(L("Pedido")): \(Self.clip(first, 600))") }
        for p in prompts.dropFirst().suffix(4) { lines.append("• \(Self.clip(p, 200))") }
        if let r = lastReply { lines.append("\(L("Resultado")): \(Self.clip(r, 900))") }
        if !files.isEmpty {
            lines.append("\(L("Arquivos")): " + files.prefix(25).joined(separator: ", ") + (files.count > 25 ? " (+\(files.count - 25))" : ""))
        }
        if !commands.isEmpty { lines.append("\(L("Comandos")): " + commands.prefix(8).joined(separator: " · ")) }
        return SecretScrubber.scrub(lines.joined(separator: "\n"))
    }

    var summary: String { lastReply.map { SecretScrubber.scrub(Self.clip($0, 200)) } ?? "" }

    static func clip(_ s: String, _ max: Int) -> String {
        let one = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return one.count > max ? String(one.prefix(max - 1)) + "…" : one
    }

    // MARK: Montagem

    private mutating func see(_ date: Date?) {
        guard let date else { return }
        if start == nil || date < start! { start = date }
        if end == nil || date > end! { end = date }
    }

    private mutating func prompt(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Marcas internas: comandos locais, avisos do sistema, contexto injetado pelo agente
        let injected = ["<local-command", "<command-", "Caveat:", "<environment_context", "<user_instructions", "<permissions", "# AGENTS.md",
                        "<user-prompt-submit-hook", "<task-notification", "<turn_aborted"]
        guard !t.isEmpty, !injected.contains(where: t.hasPrefix) else { return }
        // Só a parte de verdade: sem os <system-reminder> e afins
        let clean = t.replacingOccurrences(of: "<(system-reminder|ide_[a-z_]+|pasted_content)( [^>]*)?>[\\s\\S]*?</\\1>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, prompts.last != clean else { return }
        prompts.append(clean)
    }

    private mutating func touched(_ path: String) {
        var p = path
        if let cwd, p.hasPrefix(cwd + "/") { p = String(p.dropFirst(cwd.count + 1)) }
        guard !p.isEmpty, !files.contains(p) else { return }
        files.append(p)
    }

    private mutating func ran(_ command: String) {
        steps += 1
        let c = AgentHookCommand.oneLine(AgentStep.clean(command), 80)
        guard !c.isEmpty, !commands.contains(c), commands.count < 20 else { return }
        commands.append(c)
    }

    /// Uma linha do .jsonl do Claude Code
    mutating func feedClaude(_ o: [String: Any]) {
        if o["isSidechain"] as? Bool == true || o["isMeta"] as? Bool == true { return }
        if let s = o["sessionId"] as? String, sessionID.isEmpty { sessionID = s }
        switch o["type"] as? String {
        case "ai-title": aiTitle = (o["aiTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        case "summary": if aiTitle == nil { aiTitle = o["summary"] as? String }
        case "user", "assistant":
            if let c = o["cwd"] as? String, !c.isEmpty { cwd = c }
            if let b = o["gitBranch"] as? String, !b.isEmpty, b != "HEAD" { branch = b }
            see((o["timestamp"] as? String).flatMap(AgentDates.parse))
            let msg = o["message"] as? [String: Any] ?? [:]
            let isUser = o["type"] as? String == "user"
            if let s = msg["content"] as? String {
                if isUser { prompt(s) } else { lastReply = s }
                return
            }
            var texts: [String] = []
            for part in msg["content"] as? [[String: Any]] ?? [] {
                switch part["type"] as? String {
                case "text": if let t = part["text"] as? String { texts.append(t) }
                case "tool_use":
                    steps += 1
                    let name = (part["name"] as? String ?? "").lowercased()
                    let input = part["input"] as? [String: Any] ?? [:]
                    if ["edit", "write", "multiedit", "notebookedit"].contains(name),
                       let f = (input["file_path"] ?? input["notebook_path"]) as? String { touched(f) }
                    if name == "bash", let c = input["command"] as? String { steps -= 1; ran(c) }
                default: break
                }
            }
            guard !texts.isEmpty else { return }
            let joined = texts.joined(separator: "\n")
            if isUser { prompt(joined) } else { lastReply = joined }
        default: break
        }
    }

    /// Uma linha do .jsonl do Codex
    mutating func feedCodex(_ o: [String: Any]) {
        let p = o["payload"] as? [String: Any] ?? [:]
        see((o["timestamp"] as? String).flatMap(AgentDates.parse))
        switch o["type"] as? String {
        case "session_meta":
            if let id = p["id"] as? String { sessionID = id }
            if let c = p["cwd"] as? String { cwd = c }
            if let g = p["git"] as? [String: Any], let b = g["branch"] as? String, !b.isEmpty { branch = b }
        case "turn_context":
            if cwd == nil, let c = p["cwd"] as? String { cwd = c }
        case "event_msg":
            switch p["type"] as? String {
            case "user_message": if let m = p["message"] as? String { prompt(m) }
            case "agent_message": if let m = p["message"] as? String { lastReply = m }
            default: break
            }
        case "response_item":
            switch p["type"] as? String {
            case "message":
                let texts = (p["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
                guard !texts.isEmpty else { return }
                if p["role"] as? String == "user" { prompt(texts.joined(separator: "\n")) }
                else if p["role"] as? String == "assistant" { lastReply = texts.joined(separator: "\n") }
            case "custom_tool_call", "function_call":
                let name = p["name"] as? String ?? ""
                var input = p["input"] as? String ?? ""
                if let args = p["arguments"] as? String, let d = args.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    if let c = obj["cmd"] as? String ?? obj["command"] as? String { ran(c); return }
                    if let parts = obj["command"] as? [String], let last = parts.last { ran(last); return }
                    input = obj["input"] as? String ?? obj["patch"] as? String ?? input
                }
                steps += 1
                if name == "apply_patch" || input.hasPrefix("*** Begin Patch") {
                    for line in input.split(whereSeparator: \.isNewline) {
                        for marker in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(marker) {
                            touched(String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                }
            default: break
            }
        default: break
        }
    }

    /// Uma conversa inteira do Gemini CLI (o arquivo JSON é reescrito a cada mensagem)
    static func gemini(_ data: Data) -> AgentSessionDigest? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = obj["messages"] as? [[String: Any]] else { return nil }
        var d = AgentSessionDigest(agent: .gemini)
        d.sessionID = obj["sessionId"] as? String ?? ""
        d.see((obj["startTime"] as? String).flatMap(AgentDates.parse))
        for m in messages {
            d.see((m["timestamp"] as? String).flatMap(AgentDates.parse))
            let text: String? = (m["content"] as? String) ?? (m["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
            switch m["type"] as? String {
            case "user": if let text { d.prompt(text) }
            case "gemini":
                if let text, !text.isEmpty { d.lastReply = text }
                for call in m["toolCalls"] as? [[String: Any]] ?? [] {
                    let args = call["args"] as? [String: Any] ?? [:]
                    if let c = args["command"] as? String { d.ran(c); continue }
                    d.steps += 1
                    if ["write_file", "replace", "edit"].contains(call["name"] as? String ?? ""),
                       let f = (args["file_path"] ?? args["absolute_path"]) as? String { d.touched(f) }
                }
            default: break
            }
        }
        return d
    }
}

/// Lê as sessões dos agentes numa fila própria, só o que mudou: guarda até onde leu cada arquivo e, quando a sessão
/// fica parada por 2 minutos, atualiza o item dela na Memória (um item por sessão, nunca duplicado)
final class AgentSessionFeed: @unchecked Sendable {
    static let shared = AgentSessionFeed()

    private struct FileState {
        var offset: UInt64 = 0
        var carry = Data()
        var digest: AgentSessionDigest
        var emitted: AgentSessionDigest?
    }

    private let queue = DispatchQueue(label: "menew.memory-feed", qos: .utility)
    private var files: [String: FileState] = [:]
    /// Arquivo → data de modificação já guardada (sobrevive a reiniciar o app)
    private var done: [String: Double] = [:]
    private var loaded = false
    private var timer: Timer?
    static let quiet: TimeInterval = 120
    private static let doneKey = "memory.auto.sessions.done"

    @MainActor func refresh() {
        let on = AgentKind.allCases.filter { Self.source($0).isOn }
        timer?.invalidate()
        timer = nil
        guard !on.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in self?.scan(on) }
        timer?.tolerance = 20
        scan(on)
    }

    static func source(_ a: AgentKind) -> MemoryFeed.Source {
        switch a { case .claude: .claude; case .codex: .codex; case .gemini: .gemini }
    }

    private func scan(_ agents: [AgentKind]) {
        queue.async { [self] in
            if !loaded { done = UserDefaults.standard.dictionary(forKey: Self.doneKey) as? [String: Double] ?? [:]; loaded = true }
            let digests = scanNow(agents, now: Date())
            guard !digests.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { for d in digests { MemoryStore.shared.upsertSession(d) } }
            }
            UserDefaults.standard.set(done, forKey: Self.doneKey)
        }
    }

    /// As sessões prontas para entrar ou ser atualizadas
    func scanNow(_ agents: [AgentKind], now: Date) -> [AgentSessionDigest] {
        let cutoff = now.addingTimeInterval(-Double(MemoryFeed.backfillDays) * 86400)
        var out: [AgentSessionDigest] = []
        for agent in agents {
            let urls: [URL] = switch agent {
            case .claude: AgentUsageScanner.jsonl(under: agent.home.appendingPathComponent("projects"), cutoff: cutoff)
                .filter { !$0.path.contains("/subagents/") }
            case .codex: AgentUsageScanner.jsonl(under: agent.home.appendingPathComponent("sessions"), cutoff: cutoff)
            case .gemini: AgentUsageScanner.geminiChats(cutoff: cutoff)
            }
            for url in urls {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
                let stamp = mtime.timeIntervalSince1970
                // Já guardada assim, ou ainda em andamento: espera
                if done[url.path] == stamp || now.timeIntervalSince(mtime) < Self.quiet { continue }
                guard let d = digest(url, agent: agent) else { continue }
                done[url.path] = stamp
                if d.isWorthKeeping, files[url.path]?.emitted != d {
                    files[url.path]?.emitted = d
                    out.append(d)
                }
            }
        }
        return out
    }

    private func digest(_ url: URL, agent: AgentKind) -> AgentSessionDigest? {
        if agent == .gemini {
            guard let data = try? Data(contentsOf: url), var d = AgentSessionDigest.gemini(data) else { return nil }
            if d.sessionID.isEmpty { d.sessionID = url.deletingPathExtension().lastPathComponent }
            return d
        }
        var st = files[url.path] ?? FileState(digest: AgentSessionDigest(agent: agent))
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64 else { return nil }
        if size < st.offset { st = FileState(digest: AgentSessionDigest(agent: agent)) }
        if size > st.offset, let h = try? FileHandle(forReadingFrom: url) {
            defer { try? h.close() }
            try? h.seek(toOffset: st.offset)
            var more = true
            while more {
                more = autoreleasepool { () -> Bool in
                    guard let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
                    st.offset += UInt64(chunk.count)
                    var buf = st.carry + chunk
                    guard let lastNL = buf.lastIndex(of: 0x0A) else { st.carry = buf; return true }
                    st.carry = buf[(lastNL + 1)...].isEmpty ? Data() : Data(buf[(lastNL + 1)...])
                    buf = buf[..<lastNL]
                    for line in buf.split(separator: 0x0A, omittingEmptySubsequences: true) {
                        Self.feed(Data(line), into: &st.digest)
                    }
                    return true
                }
            }
        }
        if st.digest.sessionID.isEmpty { st.digest.sessionID = url.deletingPathExtension().lastPathComponent }
        files[url.path] = st
        return st.digest
    }

    /// Linhas que nunca interessam (pedidos à API inteiros, fotos do histórico de arquivos) nem são abertas
    private static let skipPrefixes = [#"{"type":"api-request"#, #"{"type":"file-history-snapshot"#, #"{"type":"attachment"#,
                                       #"{"type":"token_usage_record"#, #"{"type":"world_state"#].map { Data($0.utf8) }

    static func feed(_ line: Data, into d: inout AgentSessionDigest) {
        if skipPrefixes.contains(where: { line.starts(with: $0) }) { return }
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        switch d.agent {
        case .claude: d.feedClaude(o)
        case .codex: d.feedCodex(o)
        case .gemini: break
        }
    }
}

// MARK: Ajustes

/// Os interruptores das fontes automáticas (nos Ajustes do clipboard e no menu da Memória)
struct MemoryFeedToggles: View {
    @AppStorage(MemoryFeed.Source.screenshots.key) private var screenshots = false
    @AppStorage(MemoryFeed.Source.recordings.key) private var recordings = false
    @AppStorage(MemoryFeed.Source.notes.key) private var notes = false
    @AppStorage(MemoryFeed.Source.claude.key) private var claude = false
    @AppStorage(MemoryFeed.Source.codex.key) private var codex = false
    @AppStorage(MemoryFeed.Source.gemini.key) private var gemini = false

    private func binding(_ s: MemoryFeed.Source) -> Binding<Bool> {
        switch s {
        case .screenshots: $screenshots
        case .recordings: $recordings
        case .notes: $notes
        case .claude: $claude
        case .codex: $codex
        case .gemini: $gemini
        }
    }

    /// Os agentes que não estão neste Mac não aparecem
    static var visible: [MemoryFeed.Source] { MemoryFeed.Source.allCases.filter { $0.agent?.isInstalled ?? true || $0.isOn } }

    var body: some View {
        ForEach(Array(Self.visible.enumerated()), id: \.element) { i, s in
            if i > 0 { RowDivider() }
            ToggleRow(title: s.title, detail: s.detail, icon: s.icon, isOn: binding(s))
                .onChange(of: binding(s).wrappedValue) { _, on in MemoryFeed.set(s, on) }
        }
    }
}
