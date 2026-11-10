import AppKit
import ApplicationServices
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Memória: o que passou pela sua tela e você quis guardar. Um atalho captura uma área ou janela; o Menew lê o texto,
/// anota de onde veio (app, janela, link da aba) e, com a IA do Mac, dá um título e etiquetas. Captura sempre explícita,
/// nunca a tela o tempo todo. Tudo fica numa pasta no Mac.
struct MemoryItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case capture, text, link, session, recording, note }

    var id = UUID()
    var date = Date()
    var kind: Kind
    var title: String
    var summary: String = ""
    var tags: [String] = []
    /// Pessoas, projetos, ferramentas, lugares: ligam um item ao outro no grafo
    var entities: [String] = []
    /// Texto lido da imagem, ou o próprio texto guardado
    var text: String = ""
    var app: String?
    var bundle: String?
    var window: String?
    var url: String?
    var imageFile: String?
    /// A IA já passou por aqui (título, resumo, etiquetas)
    var enriched = false
    /// De onde entrou sozinho ("shot:<pixels>", "claude:<sessão>"): não duplica e deixa atualizar a sessão
    var sourceKey: String?

    /// Tudo o que a busca olha, já sem acentos e em minúsculas
    var haystack: String {
        PaletteSearch.fold([title, summary, tags.joined(separator: " "), entities.joined(separator: " "), text, app ?? "", window ?? "", url ?? ""]
            .joined(separator: " "))
    }
}

@MainActor
final class MemoryStore: ObservableObject {
    static let shared = MemoryStore()
    static let shortcutKey = "shortcutMemory"

    @Published private(set) var items: [MemoryItem] = []
    @Published var query = ""
    /// O item aberto nos detalhes (também pelo Spotlight e pelas fontes de uma resposta)
    @Published var selectedID: UUID?
    private var spotlightWork: DispatchWorkItem?
    private(set) var dir: URL?
    private var demo = false

    var imagesDir: URL? { dir?.appendingPathComponent("images", isDirectory: true) }

    func load(base: URL) {
        let d = base.appendingPathComponent("memory", isDirectory: true)
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("images"), withIntermediateDirectories: true)
        dir = d
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: d.appendingPathComponent("memory.json")), let saved = try? dec.decode([MemoryItem].self, from: data) {
            items = saved
        }
    }

    private func save() {
        guard !demo, let dir else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(items).write(to: dir.appendingPathComponent("memory.json"), options: .atomic)
        // O Spotlight é atualizado logo depois, uma vez só para várias mudanças seguidas
        spotlightWork?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated { SpotlightMemory.index(MemoryStore.shared.items) } }
        spotlightWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }

    // MARK: Busca

    /// Todas as palavras precisam aparecer (em qualquer campo); a mais nova primeiro
    var filtered: [MemoryItem] { Self.search(items, query) }

    static func search(_ items: [MemoryItem], _ query: String) -> [MemoryItem] {
        let words = PaletteSearch.fold(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let h = item.haystack
            var toks: [String]?
            // Direto no texto ou pela raiz da palavra ("graficos" acha "gráfico")
            return words.allSatisfy { w in
                if h.contains(w) { return true }
                if toks == nil { toks = SmartClipSearch.tokens(h) }
                return toks!.contains { SmartClipSearch.sameRoot($0, w) }
            }
        }
    }

    func image(for item: MemoryItem) -> NSImage? {
        guard let f = item.imageFile, let dir = imagesDir else { return nil }
        return NSImage(contentsOf: dir.appendingPathComponent(f))
    }

    // MARK: Guardar

    /// Atalho ou botão: escolha a área (ou espaço para uma janela) e ela vai para a memória
    func capture() {
        guard ScreenCapture.hasAccess() else { return }
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        // A origem é lida antes: durante a mira o app da frente continua o mesmo
        let origin = MemoryOrigin.current()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("menew-memory-\(UUID().uuidString).png")
        Task {
            let data: Data? = await Task.detached {
                Shell.run("/usr/sbin/screencapture", ["-i", "-x", file.path])
                defer { try? FileManager.default.removeItem(at: file) }
                return try? Data(contentsOf: file)
            }.value
            guard let data else { return }   // esc cancela
            add(imageData: data, origin: origin)
        }
    }

    func has(sourceKey: String) -> Bool { items.contains { $0.sourceKey == sourceKey } }

    /// `auto`: veio de uma fonte automática (sem aviso na tela, texto lido sem segredos, IA na fila)
    func add(imageData: Data, origin: MemoryOrigin, sourceKey: String? = nil, auto: Bool = false, date: Date = Date()) {
        if let sourceKey, has(sourceKey: sourceKey) { return }
        guard let dir = imagesDir, let image = NSImage(data: imageData),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        var item = MemoryItem(kind: .capture, title: origin.window ?? origin.app ?? L("Captura"))
        item.date = date
        item.app = origin.app
        item.bundle = origin.bundle
        item.window = origin.window
        item.url = origin.url
        item.sourceKey = sourceKey ?? ImageFingerprint.key(imageData)
        let name = "\(item.id.uuidString).png"
        try? imageData.write(to: dir.appendingPathComponent(name))
        item.imageFile = name
        insertByDate(item)
        save()
        if !auto { HUD.show(icon: "brain.head.profile", color: .pink, text: L("Guardado na memória")) }
        Task {
            let read = await TextRecognizer.recognize(cg)
            let text = auto ? SecretScrubber.scrub(read) : read
            update(item.id) {
                $0.text = text
                // Sem IA, o título vem da primeira linha com conteúdo
                if $0.title == L("Captura") || $0.title.isEmpty || $0.title == $0.app, let first = Self.firstLine(text) { $0.title = first }
            }
            if auto { queueEnrich(item.id) } else { await enrich(item.id) }
        }
    }

    /// Mais novos primeiro: o que entra do passado (sessões e prints antigos) vai para o seu lugar na fila
    private func insertByDate(_ item: MemoryItem) {
        let i = items.firstIndex { $0.date <= item.date } ?? items.endIndex
        items.insert(item, at: i)
    }

    /// Uma sessão de agente: cria o item ou atualiza o da mesma sessão
    func upsertSession(_ d: AgentSessionDigest) {
        let text = d.text
        let date = d.end ?? Date()
        if let i = items.firstIndex(where: { $0.sourceKey == d.sourceKey }) {
            guard items[i].text != text else { return }
            var item = items.remove(at: i)
            item.text = text
            item.date = date
            if !item.enriched { item.title = d.title; item.summary = d.summary }
            item.enriched = false
            insertByDate(item)
            save()
            queueEnrich(item.id)
            return
        }
        var item = MemoryItem(kind: .session, title: d.title)
        item.date = date
        item.summary = d.summary
        item.text = text
        item.app = d.agent.name
        item.window = d.project
        item.tags = [d.agent.short.lowercased(), PaletteSearch.fold(d.project)]
        item.entities = [d.project]
        item.sourceKey = d.sourceKey
        insertByDate(item)
        save()
        queueEnrich(item.id)
    }

    /// Espelha uma fonte (gravações, notas): cria e atualiza os itens dela e tira os que sumiram da origem
    /// (nota apagada ou protegida, gravação apagada). `prefix` é o começo do `sourceKey` dessa fonte.
    func sync(prefix: String, _ entries: [MirrorEntry]) {
        var changed = false
        let keep = Set(entries.map(\.sourceKey))
        let gone = items.filter { ($0.sourceKey?.hasPrefix(prefix) ?? false) && !keep.contains($0.sourceKey!) }
        for g in gone { items.removeAll { $0.id == g.id }; changed = true }
        for e in entries {
            if let i = items.firstIndex(where: { $0.sourceKey == e.sourceKey }) {
                guard items[i].text != e.text || items[i].title != e.title else { continue }
                var item = items.remove(at: i)
                e.apply(to: &item)
                insertByDate(item)
            } else {
                var item = MemoryItem(kind: e.kind, title: e.title)
                e.apply(to: &item)
                insertByDate(item)
            }
            changed = true
        }
        if changed { save() }
    }

    /// A IA do Mac passa por um item de cada vez: muitas sessões de uma vez não travam nada
    private var enrichQueue: [UUID] = []
    private var enriching = false

    func queueEnrich(_ id: UUID) {
        guard !demo else { return }
        if !enrichQueue.contains(id) { enrichQueue.append(id) }
        guard !enriching else { return }
        enriching = true
        Task {
            while !enrichQueue.isEmpty {
                let next = enrichQueue.removeFirst()
                await enrich(next)
            }
            enriching = false
        }
    }

    /// Um texto ou link copiado, guardado de propósito (do clipboard ou da paleta)
    func add(text: String, origin: MemoryOrigin = MemoryOrigin()) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let isLink = URL(string: t).map { $0.scheme?.hasPrefix("http") == true } ?? false
        var item = MemoryItem(kind: isLink ? .link : .text, title: Self.firstLine(t) ?? L("Texto"))
        item.text = t
        item.url = isLink ? t : origin.url
        item.app = origin.app
        item.bundle = origin.bundle
        items.insert(item, at: 0)
        save()
        HUD.show(icon: "brain.head.profile", color: .pink, text: L("Guardado na memória"))
        Task { await enrich(item.id) }
    }

    func delete(_ item: MemoryItem) {
        if let f = item.imageFile, let dir = imagesDir { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        items.removeAll { $0.id == item.id }
        save()
    }

    func eraseAll() {
        for i in items { if let f = i.imageFile, let dir = imagesDir { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) } }
        items = []
        save()
    }

    func update(_ id: UUID, _ change: (inout MemoryItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        save()
    }

    static func firstLine(_ s: String) -> String? {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.count >= 3 }.map { String($0.prefix(90)) }
    }

    // MARK: IA

    /// Título, resumo, etiquetas e entidades com o modelo do Mac. Sem Apple Intelligence, o item fica como está.
    func enrich(_ id: UUID) async {
        guard AIFeature.memory.isOn, AIText.unavailableReason == nil, let item = items.first(where: { $0.id == id }) else { return }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let source = [item.app.map { "App: \($0)" }, item.window.map { "Window: \($0)" }, item.url.map { "Link: \($0)" }]
                .compactMap { $0 }.joined(separator: "\n")
            let session = LanguageModelSession(instructions: """
                You file things a person saved from their screen so they can find them later. \
                Write in the same language as the content. Be specific: name the tool, library, product, person or topic.
                """)
            do {
                let r = try await session.respond(to: "\(source)\n\nContent:\n\(String(item.text.prefix(3000)))", generating: MemoryTags.self)
                let tags = r.content
                update(id) {
                    if !tags.title.isEmpty { $0.title = String(tags.title.prefix(90)) }
                    $0.summary = tags.summary
                    $0.tags = Array(tags.tags.prefix(6)).map { $0.lowercased() }
                    $0.entities = Array(tags.entities.prefix(8))
                    $0.enriched = true
                }
            } catch {}
        }
        #endif
    }

    /// Itens antigos (de antes da IA estar ligada) ganham título e etiquetas aos poucos
    func enrichPending() {
        let pending = items.filter { !$0.enriched }.prefix(20).map(\.id)
        guard !pending.isEmpty else { return }
        Task { for id in pending { await enrich(id) } }
    }

    // MARK: Exemplo

    func showDemo() {
        demo = true
        let now = Date()
        func make(_ kind: MemoryItem.Kind, _ title: String, _ summary: String, _ tags: [String], _ app: String, _ url: String?, _ hoursAgo: Double, _ entities: [String]) -> MemoryItem {
            var i = MemoryItem(kind: kind, title: title)
            i.date = now.addingTimeInterval(-hoursAgo * 3600)
            i.summary = summary; i.tags = tags; i.app = app; i.url = url; i.entities = entities; i.enriched = true
            return i
        }
        items = [
            make(.session, L("Busca por raiz de palavra na Memória"), L("“gráficos” agora acha “gráfico”; testes passando."),
                 ["claude", "menew"], "Claude Code", nil, 1, ["Menew", "SwiftUI"]),
            make(.capture, L("Swift Charts: gráfico de linhas com área"), L("Exemplo de LineMark e AreaMark com gradiente, da documentação da Apple."),
                 ["swift", "gráficos", "swiftui"], "Safari", "https://developer.apple.com/documentation/charts", 3, ["Swift Charts", "SwiftUI", "Apple"]),
            make(.link, L("Firebase: regras de segurança do Firestore"), L("Como permitir leitura só para o dono do documento."),
                 ["firebase", "segurança"], "Google Chrome", "https://firebase.google.com/docs/firestore/security", 26, ["Firebase", "Firestore"]),
            make(.capture, L("Erro de assinatura no build"), L("“No signing certificate” no Xcode; resolvido escolhendo o time certo."),
                 ["xcode", "erro", "assinatura"], "Xcode", nil, 50, ["Xcode", "Developer ID"]),
            make(.text, L("Ideia: app de menu bar com grafo"), L("Ligar notas, capturas e links por assunto, montado pela IA."),
                 ["ideia", "menew"], "Notas", nil, 75, ["Menew", "Obsidian"]),
            make(.capture, L("Paleta de cores do projeto"), L("Índigo #5C6BFF e violeta #9E40F2 para o site."),
                 ["design", "cores"], "Figma", nil, 120, ["Menew", "Figma"]),
            make(.link, L("SwiftUI: Layout personalizado"), L("Protocolo Layout para posicionar etiquetas em fluxo."),
                 ["swiftui", "layout"], "Safari", "https://developer.apple.com/documentation/swiftui/layout", 140, ["SwiftUI", "Apple"]),
            make(.capture, L("Reunião com a Ana sobre o lançamento"), L("Lançamento na quinta; Ana revisa o site, Bruno os textos."),
                 ["reunião", "lançamento"], "Zoom", nil, 30, ["Ana", "Bruno", "Menew"]),
            make(.text, L("Ideia de nome para o plano Pro"), L("Testar com a Ana antes de decidir."),
                 ["ideia", "produto"], "Notas", nil, 200, ["Ana", "Menew"]),
        ]
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct MemoryTags {
    @Guide(description: "Short specific title, under 70 characters")
    var title: String
    @Guide(description: "One sentence saying what this is and why it may matter later")
    var summary: String
    @Guide(description: "Two to five lowercase topic tags")
    var tags: [String]
    @Guide(description: "Named things mentioned: tools, libraries, products, companies, people, projects")
    var entities: [String]
}
#endif

/// De onde veio a captura: o app da frente, a janela e, nos navegadores, o link da aba
struct MemoryOrigin {
    var app: String?
    var bundle: String?
    var window: String?
    var url: String?

    @MainActor static func current() -> MemoryOrigin {
        var o = MemoryOrigin()
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier else { return o }
        o.app = front.localizedName
        o.bundle = front.bundleIdentifier
        o.window = Self.windowTitle(pid: front.processIdentifier)
        o.url = Self.browserURL(front.bundleIdentifier)
        return o
    }

    /// Título da janela da frente (Acessibilidade, se permitida)
    private static func windowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success, let win else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let t = title as? String, !t.isEmpty else { return nil }
        return t
    }

    /// Link da aba aberta. Na primeira vez o macOS pergunta se o Menew pode falar com o navegador.
    private static func browserURL(_ bundle: String?) -> String? {
        let script: String? = switch bundle {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            "tell application id \"\(bundle!)\" to return URL of front document"
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera":
            "tell application id \"\(bundle!)\" to return URL of active tab of front window"
        default: nil
        }
        guard let script, let s = NSAppleScript(source: script) else { return nil }
        var err: NSDictionary?
        let r = s.executeAndReturnError(&err).stringValue
        return r?.hasPrefix("http") == true ? r : nil
    }
}
