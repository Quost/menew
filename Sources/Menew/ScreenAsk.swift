import AppKit
import NaturalLanguage
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Pergunte sobre a tela: selecione uma área (um erro, um gráfico, um texto em outra língua), o Menew lê o texto dela
/// no próprio Mac e responde o que você perguntar com a IA do Mac. Sem a IA, mostra o texto lido para copiar.
@MainActor
final class ScreenAsk: ObservableObject {
    static let shared = ScreenAsk()

    @Published var image: NSImage?
    @Published var screenText = ""
    @Published var question = ""
    @Published var asked = ""
    @Published var answer = ""
    @Published var working = false
    @Published var failed = false
    private var window: NSPanel?

    /// Perguntas prontas, em inglês para o modelo; o título aparece no idioma do app
    enum Quick: CaseIterable {
        case explain, summarize, translate, next
        var title: String {
            switch self {
            case .explain: L("Explicar")
            case .summarize: L("Resumir")
            case .translate: L("Traduzir")
            case .next: L("O que eu faço?")
            }
        }
    }

    func start() {
        guard ScreenCapture.hasAccess() else { return }
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("menew-ask-\(UUID().uuidString).png")
        Task {
            let result: (NSImage, String)? = await Task.detached {
                Shell.run("/usr/sbin/screencapture", ["-i", "-x", file.path])
                defer { try? FileManager.default.removeItem(at: file) }
                guard let data = try? Data(contentsOf: file), let img = NSImage(data: data) else { return nil } // esc: cancelou
                return (img, await TextRecognizer.recognize(url: file))
            }.value
            guard let (img, text) = result else { return }
            open(image: img, text: text)
        }
    }

    func open(image: NSImage?, text: String) {
        self.image = image
        screenText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        question = ""
        asked = ""
        answer = ""
        failed = false
        guard !screenText.isEmpty else {
            HUD.show(icon: "text.viewfinder", color: .orange, text: L("Nenhum texto encontrado"))
            return
        }
        let w = window ?? make()
        window = w
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func ask(_ q: Quick) {
        let prompt: String = switch q {
        case .explain: "Explain what this text means in simple words."
        case .summarize: "Summarize this text in two or three sentences."
        case .translate: "Translate this text into \(Locale(identifier: "en").localizedString(forLanguageCode: L10n.current.rawValue) ?? "English")."
        case .next: "What should I do about this? Give short, concrete steps."
        }
        run(title: q.title, prompt: prompt, language: nil)
    }

    func askTyped() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        run(title: q, prompt: q, language: q)
    }

    private func run(title: String, prompt: String, language sample: String?) {
        guard AIText.unavailableReason == nil, !working else { return }
        asked = title
        answer = ""
        failed = false
        working = true
        let text = String(screenText.prefix(3500))
        // A resposta sai no idioma da pergunta digitada, ou no do app para as prontas
        let lang = sample.flatMap { NLLanguageName.of($0) } ?? Locale(identifier: "en").localizedString(forLanguageCode: L10n.current.rawValue) ?? "English"
        Task {
            do {
                try await Self.stream(text: text, prompt: prompt, language: lang) { self.answer = $0 }
            } catch {
                failed = true
            }
            working = false
        }
    }

    static func stream(text: String, prompt: String, language: String, onPartial: @escaping @MainActor (String) -> Void) async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(model: .default, instructions: """
                You help with text the user captured from their screen. Base the answer on that text. \
                Be clear and concise. Write in \(language).
                """)
            for try await snapshot in session.streamResponse(to: "Screen text:\n\(text)\n\nRequest: \(prompt)") {
                await onPartial(snapshot.content)
            }
            return
        }
        #endif
        throw CancellationError()
    }

    func close() { window?.orderOut(nil) }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: ScreenAskView(model: self))
        return p
    }
}

/// "Portuguese", "German"…: o idioma de um texto, em inglês, para o pedido ao modelo
enum NLLanguageName {
    static func of(_ text: String) -> String? {
        guard let code = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
    }
}

struct ScreenAskView: View {
    @ObservedObject var model: ScreenAsk
    @State private var showText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let img = model.image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 120, maxHeight: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Pergunte sobre a tela")).font(.system(size: 14, weight: .bold))
                    if AIText.unavailableReason == nil {
                        Button(showText ? L("Esconder texto lido") : L("Ver texto lido (%d linhas)", model.screenText.split(separator: "\n").count)) {
                            showText.toggle()
                        }
                        .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.accentColor)
                    }
                }
                Spacer()
            }
            if showText || AIText.unavailableReason != nil {
                ScrollView {
                    Text(model.screenText).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: AIText.unavailableReason != nil ? .infinity : 110)
                .card(padding: 8)
            }
            if let reason = AIText.unavailableReason {
                Text(L("Com a Apple Intelligence, dá para perguntar sobre esse texto. (%@)", reason))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(ScreenAsk.Quick.allCases, id: \.self) { q in
                        Button(q.title) { model.ask(q) }
                            .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .disabled(model.working)
                    }
                }
                HStack(spacing: 8) {
                    TextField(L("Pergunte qualquer coisa sobre isso…"), text: $model.question)
                        .textFieldStyle(.roundedBorder).onSubmit { model.askTyped() }
                    PillButton(title: L("Perguntar"), icon: "arrow.up", primary: true) { model.askTyped() }
                        .disabled(model.working || model.question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !model.asked.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "apple.intelligence").foregroundStyle(.pink)
                            Text(model.asked).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                            if model.working { ProgressView().controlSize(.mini) }
                        }
                        ScrollView {
                            Text(model.failed ? L("A IA não conseguiu responder") : (model.answer.isEmpty ? L("Pensando…") : model.answer))
                                .font(.system(size: 12.5)).lineSpacing(2).textSelection(.enabled)
                                .foregroundStyle(model.answer.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .padding(10).frame(maxHeight: .infinity, alignment: .top).card(padding: 0)
                } else {
                    Spacer(minLength: 0)
                }
            }
            HStack {
                Text(L("No seu Mac, sem internet")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                PillButton(title: L("Fechar"), icon: "xmark") { model.close() }.keyboardShortcut(.cancelAction)
                PillButton(title: L("Copiar"), icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.answer.isEmpty ? model.screenText : model.answer, forType: .string)
                    HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
                }
                .disabled(model.working)
            }
        }
        .padding(.horizontal, 16).padding(.top, 30).padding(.bottom, 14)
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 440, maxHeight: .infinity, alignment: .top)
        .background(VisualEffect(material: .popover).ignoresSafeArea())
    }
}
