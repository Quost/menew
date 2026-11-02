import AppKit
import CoreSpotlight
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Perguntar à memória: "qual era aquela biblioteca de gráficos em Swift?". A IA do Mac transforma a pergunta em
/// termos de busca (com sinônimos e traduções), o Menew procura na memória, nas notas e no clipboard, e a IA
/// responde com base no que achou, mostrando as fontes. Tudo no Mac.
@MainActor
final class MemoryAsk: ObservableObject {
    static let shared = MemoryAsk()

    struct Source: Identifiable, Equatable {
        enum Kind: Equatable { case memory(UUID), note(UUID), clip(UUID) }
        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String
        let text: String
    }

    @Published private(set) var question = ""
    @Published private(set) var answer = ""
    @Published private(set) var sources: [Source] = []
    @Published private(set) var working = false
    @Published private(set) var failed = false

    var available: Bool { AIFeature.memory.isOn && AIText.unavailableReason == nil }

    func clear() {
        question = ""; answer = ""; sources = []; failed = false
    }

    func ask(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !working else { return }
        question = q
        answer = ""
        sources = []
        failed = false
        working = true
        Task {
            let terms = await Self.terms(for: q)
            let found = Self.retrieve(terms)
            sources = found
            if found.isEmpty {
                answer = L("Não achei nada sobre isso na sua memória, nas notas ou no clipboard.")
            } else if let a = await Self.answer(q, found) {
                answer = a
            } else {
                failed = true
            }
            working = false
        }
    }

    // MARK: Busca

    /// Termos de busca: a IA amplia com sinônimos e traduções; sem IA, as palavras da pergunta
    static func terms(for q: String) async -> [String] {
        let base = SmartClipSearch.tokens(q).filter { $0.count >= 3 && !stopwords.contains($0) }
        #if canImport(FoundationModels)
        if #available(macOS 26, *), AIText.unavailableReason == nil {
            let session = LanguageModelSession(instructions: """
                Turn a question about something the user saved into search terms. Include the key nouns and names, \
                synonyms, singular forms, and their translations to English and Portuguese, using the words people use \
                in software and design (for example "gráficos" also gives "chart", "charts", "plot"). No full sentences.
                """)
            if let r = try? await session.respond(to: q, generating: SearchTerms.self) {
                let extra = r.content.terms.flatMap { SmartClipSearch.tokens($0) }.filter { $0.count >= 3 && !stopwords.contains($0) }
                return Array(Set(base + extra))
            }
        }
        #endif
        return base
    }

    static let stopwords: Set<String> = ["qual", "quais", "que", "aquele", "aquela", "aquilo", "era", "foi", "para", "com", "uma", "the", "what",
        "which", "was", "that", "where", "onde", "como", "how", "semana", "passada", "week", "last", "encontrei", "found", "vi", "saw", "sobre",
        "about", "meu", "minha", "my", "isso", "this", "ontem", "yesterday", "hoje", "today", "der", "die", "das", "und", "welche", "cual", "una", "esa"]

    /// Os 6 itens com mais termos em comum (memória pesa um pouco mais: foi guardado de propósito)
    static func retrieve(_ terms: [String]) -> [Source] {
        guard !terms.isEmpty else { return [] }
        var scored: [(Double, Source)] = []
        func score(_ text: String) -> Double {
            let toks = Set(SmartClipSearch.tokens(text))
            return Double(terms.filter { t in toks.contains(t) || toks.contains { SmartClipSearch.sameRoot($0, t) } }.count)
        }
        for m in MemoryStore.shared.items {
            let s = score(m.haystack)
            if s > 0 {
                scored.append((s + 1.5, Source(kind: .memory(m.id), title: m.title, detail: [m.app, m.url.flatMap { URL(string: $0)?.host }]
                    .compactMap { $0 }.joined(separator: " · "), text: [m.summary, m.text].joined(separator: "\n"))))
            }
        }
        if let notes = (NSApp.delegate as? AppDelegate)?.notes.notes {
            for n in notes where !n.secure && !n.isPasswords {
                let s = score(n.text)
                if s > 0 { scored.append((s, Source(kind: .note(n.id), title: n.title, detail: L("Nota"), text: n.text))) }
            }
        }
        if let clips = (NSApp.delegate as? AppDelegate)?.clipboard.items {
            for c in clips.prefix(300) where c.kind == .text {
                guard let t = c.text else { continue }
                let s = score(t)
                // Clipboard tem muita coisa solta: precisa de pelo menos dois termos em comum
                if s >= 2 { scored.append((s - 0.5, Source(kind: .clip(c.id), title: c.title, detail: [L("Clipboard"), c.sourceApp].compactMap { $0 }.joined(separator: " · "), text: t))) }
            }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(6).map(\.1)
    }

    // MARK: Resposta

    static func answer(_ q: String, _ sources: [Source]) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), AIText.unavailableReason == nil {
            let context = sources.enumerated().map { i, s in
                "[\(i + 1)] \(s.title)\(s.detail.isEmpty ? "" : " — " + s.detail)\n\(String(s.text.prefix(700)))"
            }.joined(separator: "\n\n")
            let session = LanguageModelSession(instructions: """
                Answer the user's question using only the saved items below. Be brief (two or three sentences). \
                Mention which item you used as [1], [2]. If the items don't answer it, say so. \
                Reply in the language of the question.
                """)
            return try? await session.respond(to: "Saved items:\n\(context)\n\nQuestion: \(q)").content
        }
        #endif
        // Sem IA: as fontes já são a resposta
        return L("Achei %d itens que combinam com a pergunta:", sources.count)
    }

    /// Abre a fonte: o item na memória, a nota, ou copia o texto do clipboard
    func open(_ s: Source) {
        switch s.kind {
        case .memory(let id): MemoryStore.shared.selectedID = id
        case .note(let id): (NSApp.delegate as? AppDelegate)?.openNote(id)
        case .clip:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s.text, forType: .string)
            HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
        }
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct SearchTerms {
    @Guide(description: "Eight to fourteen short search terms")
    var terms: [String]
}
#endif

/// A resposta, logo abaixo da busca da memória
struct MemoryAnswerView: View {
    @ObservedObject var ask = MemoryAsk.shared

    var body: some View {
        if ask.working || !ask.answer.isEmpty || ask.failed {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.violet)
                    Text(ask.question).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button { ask.clear() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(L("Fechar"))
                }
                if ask.working {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Procurando na sua memória…")).foregroundStyle(.secondary) }
                        .font(.system(size: 12.5))
                } else if ask.failed {
                    Text(L("A IA não conseguiu responder agora.")).font(.system(size: 12.5)).foregroundStyle(.orange)
                } else {
                    Text((try? AttributedString(markdown: ask.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(ask.answer))
                        .font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if !ask.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(ask.sources.enumerated()), id: \.element.id) { i, s in
                            Button { ask.open(s) } label: {
                                HStack(spacing: 6) {
                                    Text("[\(i + 1)]").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.violet).monospacedDigit()
                                    Text(s.title).font(.system(size: 12)).lineLimit(1)
                                    Text(s.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.violet.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.violet.opacity(0.25)))
        }
    }
}

// MARK: Paleta

extension MemoryAsk {
    static let prefixes = ["lembra ", "lembrar ", "memoria ", "memória ", "remember ", "recall ", "erinnere ", "recuerda ", "记得 "]

    /// "lembra qual era aquele app de menu bar" na paleta
    static func paletteItem(raw: String) -> PaletteItem? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let prefix = prefixes.first(where: { text.lowercased().hasPrefix($0) }) else { return nil }
        let q = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return nil }
        return PaletteItem(id: "memory.ask", kind: .calc, title: L("Perguntar à memória: %@", q), subtitle: L("Na memória, nas notas e no clipboard"),
                           keywords: text, icon: .symbol("brain.head.profile", .pink), remember: false) {
            MemoryWindow.shared.show(query: "")
            MemoryAsk.shared.ask(q)
        }
    }
}

// MARK: Spotlight

/// As capturas da memória também aparecem no Spotlight; escolher abre o item no Menew
@MainActor
enum SpotlightMemory {
    static let domain = "com.matheusquost.menew.memory"

    static func index(_ items: [MemoryItem]) {
        let index = CSSearchableIndex.default()
        guard SpotlightNotes.shared.isOn else { index.deleteSearchableItems(withDomainIdentifiers: [domain]); return }
        let list = items.map { m -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = m.title
            a.contentDescription = m.summary.isEmpty ? m.app : m.summary
            a.textContent = m.text
            a.keywords = m.tags + m.entities + ["Menew"]
            a.contentModificationDate = m.date
            let item = CSSearchableItem(uniqueIdentifier: "memory:\(m.id.uuidString)", domainIdentifier: domain, attributeSet: a)
            item.expirationDate = .distantFuture
            return item
        }
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in index.indexSearchableItems(list) }
    }

    static func memoryID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, id.hasPrefix("memory:") else { return nil }
        return UUID(uuidString: String(id.dropFirst(7)))
    }
}
