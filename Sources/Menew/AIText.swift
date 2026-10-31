import AppKit
import NaturalLanguage
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// IA no próprio Mac (Apple Intelligence, modelo local): resumir, reescrever, corrigir e traduzir o texto copiado.
/// Só o modelo do aparelho é usado, nunca o da nuvem; nada sai do Mac. Precisa do macOS 26 e da Apple Intelligence ligada.
enum AIAction: String, CaseIterable {
    case summarize, clearer, formal, friendly, shorter, fix, toEnglish, toPortuguese, toSpanish, toGerman, toChinese

    @MainActor var title: String {
        switch self {
        case .summarize: L("Resumir com IA")
        case .clearer: L("Reescrever mais claro")
        case .formal: L("Reescrever mais formal")
        case .friendly: L("Reescrever mais amigável")
        case .shorter: L("Encurtar o texto")
        case .fix: L("Corrigir ortografia e gramática")
        case .toEnglish: L("Traduzir para o inglês")
        case .toPortuguese: L("Traduzir para o português")
        case .toSpanish: L("Traduzir para o espanhol")
        case .toGerman: L("Traduzir para o alemão")
        case .toChinese: L("Traduzir para o chinês")
        }
    }

    var icon: String {
        switch self {
        case .summarize: "text.badge.star"
        case .clearer, .formal, .friendly, .shorter: "pencil.and.outline"
        case .fix: "checkmark.seal"
        default: "globe"
        }
    }

    var keywords: String {
        let own: String = switch self {
        case .summarize: "resumir resumo summarize summary tldr zusammenfassen resumen 总结 摘要"
        case .clearer: "reescrever rewrite claro clearer simples simple umschreiben reescribir 改写 清晰"
        case .formal: "reescrever rewrite formal profissional professional email förmlich 正式"
        case .friendly: "reescrever rewrite amigável amigavel friendly casual informal freundlich amable 友好"
        case .shorter: "encurtar curto shorter short conciso concise kürzen acortar 缩短 精简"
        case .fix: "corrigir revisar fix grammar gramática ortografia spelling typos korrigieren corregir 纠正 语法"
        case .toEnglish: "traduzir translate inglês ingles english übersetzen englisch traducir inglés 翻译 英语"
        case .toPortuguese: "traduzir translate português portugues portuguese übersetzen portugiesisch traducir 翻译 葡萄牙语"
        case .toSpanish: "traduzir translate espanhol spanish übersetzen spanisch traducir español 翻译 西班牙语"
        case .toGerman: "traduzir translate alemão alemao german deutsch übersetzen traducir alemán 翻译 德语"
        case .toChinese: "traduzir translate chinês chines chinese chinesisch übersetzen traducir chino 翻译 中文"
        }
        return own + " ia ai inteligência inteligencia intelligence ki apple"
    }

    /// O pedido ao modelo, em inglês (o modelo segue melhor); a resposta sai no idioma do texto, salvo nas traduções
    var isTranslation: Bool { rawValue.hasPrefix("to") }

    var prompt: String {
        switch self {
        case .summarize: """
            Summarize the main point of the text in your own words, in one to three short sentences. \
            Do not copy sentences from the text, do not quote examples, and do not keep its formatting or list structure.
            """
        case .clearer: "Rewrite the text to be clearer and easier to read. Keep the meaning and the language of the text."
        case .formal: "Rewrite the text in a more formal, professional tone. Keep the meaning and the language of the text."
        case .friendly: "Rewrite the text in a warmer, friendlier tone. Keep the meaning and the language of the text."
        case .shorter: "Make the text shorter and more concise. Keep the key points and the language of the text."
        case .fix: "Fix spelling, grammar and punctuation. Change nothing else. Keep the language of the text."
        case .toEnglish: "Translate the text into English."
        case .toPortuguese: "Translate the text into Brazilian Portuguese."
        case .toSpanish: "Translate the text into Spanish."
        case .toGerman: "Translate the text into German."
        case .toChinese: "Translate the text into Simplified Chinese."
        }
    }
}

@MainActor
enum AIText {
    /// nil = pronto; senão, o motivo para mostrar na paleta
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return L("Precisa do macOS 26 ou mais novo") }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return L("Ligue a Apple Intelligence em Ajustes do Sistema")
        case .unavailable(.modelNotReady): return L("O modelo ainda está sendo baixado pelo macOS")
        case .unavailable(.deviceNotEligible): return L("Este Mac não tem Apple Intelligence")
        default: return L("A IA do Mac não está disponível agora")
        }
        #else
        return L("Precisa do macOS 26 ou mais novo")
        #endif
    }

    static func paletteItems(text: String, query: String) -> [PaletteItem] {
        let q = PaletteSearch.fold(query.trimmingCharacters(in: .whitespaces))
        guard q.count >= 2, !text.isEmpty else { return [] }
        let matches = AIAction.allCases.filter { PaletteSearch.score(q, title: $0.title, keywords: $0.keywords) != nil }
        guard !matches.isEmpty else { return [] }
        if let reason = unavailableReason {
            // Um aviso só, para quem procurou e não tem a IA
            return [PaletteItem(id: "ai.unavailable", kind: .action, title: L("IA do Mac indisponível"), subtitle: reason,
                                keywords: matches[0].keywords, icon: .symbol("apple.intelligence", .gray), remember: false) {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: reason, duration: 2.5)
            }]
        }
        let preview = String(text.prefix(60)).split(whereSeparator: \.isNewline).joined(separator: " ")
        return matches.map { a in
            PaletteItem(id: "ai.\(a.rawValue)", kind: .action, title: a.title,
                        subtitle: L("No seu Mac · “%@”", preview), keywords: a.keywords,
                        icon: .symbol(a.icon, .pink), remember: false) { run(a, on: text) }
        }
    }

    /// Roda no modelo local e põe o resultado no clipboard (e cola, se a colagem automática estiver ligada)
    static func run(_ action: AIAction, on text: String) {
        HUD.show(icon: "apple.intelligence", color: .pink, text: L("Pensando…"), duration: nil)
        Task {
            do {
                let result = try await generate(action, text)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(result, forType: .string)
                HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Pronto, copiado"))
                guard UserDefaults.standard.bool(forKey: "autoPaste"), AXIsProcessTrusted() else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { ClipboardManager.postCommandV() }
            } catch {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("A IA não conseguiu responder"), duration: 2.5)
            }
        }
    }

    /// "Portuguese", "German"…: o idioma do texto, em inglês, para o pedido ao modelo
    private static func language(of text: String) -> String? {
        guard let code = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
    }

    private static func generate(_ action: AIAction, _ text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(model: .default, instructions: """
                You edit text for the user. Reply with the resulting text only: no introduction, no quotes, \
                no explanations, no notes. Keep line breaks and lists when they make sense.
                """)
            // O modelo às vezes responde em inglês; dizer o idioma do texto evita isso
            var prompt = action.prompt
            if !action.isTranslation, let lang = language(of: text) { prompt += " Write the result in \(lang)." }
            let response = try await session.respond(to: prompt + "\n\nText:\n" + text)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw CancellationError()
    }
}

// MARK: Pergunte à IA

/// Pergunta livre na paleta ("ia como recuso uma reunião com educação?"). A resposta aparece aos poucos numa janelinha.
@MainActor
final class AIAnswer: ObservableObject {
    @Published var question = ""
    @Published var text = ""
    @Published var working = false
    @Published var failed = false

    func ask(_ q: String) {
        question = q
        text = ""
        failed = false
        working = true
        Task {
            do {
                try await AIText.stream(q) { partial in self.text = partial }
            } catch {
                failed = true
            }
            working = false
        }
    }
}

extension AIText {
    /// Palavras que começam uma pergunta na paleta, nos cinco idiomas
    static let askPrefixes = ["ia ", "ai ", "ki ", "? ", "perguntar ", "ask ", "fragen ", "preguntar ", "问 "]

    static func askItem(raw: String) -> PaletteItem? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let prefix = askPrefixes.first(where: { text.lowercased().hasPrefix($0) }) else { return nil }
        let question = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard question.count >= 3 else { return nil }
        if let reason = unavailableReason {
            return PaletteItem(id: "ai.ask", kind: .calc, title: L("IA do Mac indisponível"), subtitle: reason, keywords: text,
                               icon: .symbol("apple.intelligence", .gray), remember: false) {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: reason, duration: 2.5)
            }
        }
        return PaletteItem(id: "ai.ask", kind: .calc, title: L("Perguntar à IA: %@", question), subtitle: L("No seu Mac, sem internet"),
                           keywords: text, icon: .symbol("apple.intelligence", .pink), remember: false) {
            AIAnswerWindow.shared.ask(question)
        }
    }

    /// Resposta aos poucos (cada parte traz o texto inteiro até ali)
    static func stream(_ question: String, onPartial: @escaping @MainActor (String) -> Void) async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(model: .default, instructions: """
                You are a helpful assistant inside a Mac utility. Answer clearly and concisely. \
                Reply in the same language as the question.
                """)
            for try await snapshot in session.streamResponse(to: question) {
                await onPartial(snapshot.content)
            }
            return
        }
        #endif
        throw CancellationError()
    }

    static let noteSummary = "Summarize the note in two to four short sentences, in your own words."
    static let noteTasks = """
        List the action items in the note as a Markdown checklist, one per line, each line starting with "- [ ] ". \
        Include every concrete action someone has to do, including the ones assigned to other people (keep their names), \
        but never the note's title, subject or topics. \
        Reply with the checklist only. If there are no action items, reply with an empty message.
        """

    /// Para as notas: pede algo sobre o texto e devolve a resposta inteira
    static func ask(_ instruction: String, about text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(model: .default, instructions: """
                You help organize notes. Reply with the result only: no introduction and no explanations.
                """)
            var prompt = instruction
            if let lang = language(of: text) { prompt += " Write the result in \(lang)." }
            return try await session.respond(to: prompt + "\n\nNote:\n" + text).content
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw CancellationError()
    }
}

@MainActor
final class AIAnswerWindow: NSObject, NSWindowDelegate {
    static let shared = AIAnswerWindow()
    private let model = AIAnswer()
    private var window: NSPanel?

    func ask(_ question: String) {
        model.ask(question)
        let w = window ?? make()
        window = w
        if !w.isVisible { w.center() }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: AIAnswerView(model: model) { [weak p] in p?.close() })
        return p
    }
}

struct AIAnswerView: View {
    @ObservedObject var model: AIAnswer
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence").foregroundStyle(.pink)
                Text(model.question).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer()
                if model.working { ProgressView().controlSize(.small) }
            }
            ScrollView {
                Text(model.failed ? L("A IA não conseguiu responder") : (model.text.isEmpty ? L("Pensando…") : model.text))
                    .font(.system(size: 13)).lineSpacing(3)
                    .foregroundStyle(model.text.isEmpty || model.failed ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .card(padding: 10)
            HStack {
                Text(L("No seu Mac, sem internet")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                PillButton(title: L("Fechar"), icon: "xmark", action: close)
                    .keyboardShortcut(.cancelAction)
                PillButton(title: L("Copiar"), icon: "doc.on.doc", primary: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.text, forType: .string)
                    HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
                }
                .disabled(model.text.isEmpty || model.working)
                .keyboardShortcut("c", modifiers: .command)
            }
        }
        .padding(.horizontal, 14).padding(.top, 28).padding(.bottom, 14)
        .background(VisualEffect(material: .popover).ignoresSafeArea())
    }
}
