import AppKit
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Tradução sem internet com o tradutor da Apple (macOS 15 ou mais novo, sem precisar de Apple Intelligence).
/// Na primeira vez com um idioma novo, o próprio macOS oferece baixar o pacote; depois disso tudo roda no Mac.
@MainActor
enum Translate {
    /// Idiomas de destino: código, nome e palavras para achar na paleta (nos cinco idiomas do Menew)
    static let targets: [(code: String, name: () -> String, keywords: String)] = [
        ("en", { L("inglês") }, "ingles inglês english englisch inglés 英语"),
        ("pt", { L("português") }, "portugues português portuguese portugiesisch portugués 葡萄牙语"),
        ("es", { L("espanhol") }, "espanhol spanish spanisch español 西班牙语"),
        ("de", { L("alemão") }, "alemao alemão german deutsch alemán 德语"),
        ("fr", { L("francês") }, "frances francês french französisch francés 法语"),
        ("it", { L("italiano") }, "italiano italian italienisch 意大利语"),
        ("ja", { L("japonês") }, "japones japonês japanese japanisch japonés 日语"),
        ("zh", { L("chinês") }, "chines chinês chinese chinesisch chino 中文 汉语"),
    ]

    static var isAvailable: Bool {
        if #available(macOS 15, *) { return true }
        return false
    }

    static func paletteItems(text: String, query: String) -> [PaletteItem] {
        let q = PaletteSearch.fold(query.trimmingCharacters(in: .whitespaces))
        guard isAvailable, q.count >= 3, !text.isEmpty else { return [] }
        let base = "traduzir traducao tradução translate translation übersetzen traducir 翻译 "
        let preview = String(text.prefix(50)).split(whereSeparator: \.isNewline).joined(separator: " ")
        return targets.compactMap { t in
            let title = L("Traduzir para o %@", t.name())
            guard PaletteSearch.score(q, title: title, keywords: base + t.keywords) != nil else { return nil }
            return PaletteItem(id: "translate.\(t.code)", kind: .action, title: title, subtitle: L("Sem internet · “%@”", preview),
                               keywords: base + t.keywords, icon: .symbol("translate", .blue), remember: false) {
                TranslateWindow.shared.translate(text, to: t.code)
            }
        }
    }
}

@MainActor
final class TranslateModel: ObservableObject {
    @Published var source = ""
    @Published var result = ""
    @Published var targetName = ""
    @Published var working = false
    @Published var failed = false
    /// Mudar a configuração dispara uma nova tradução (é assim que o Translation funciona no SwiftUI)
    @Published var configToken = UUID()
    var target = "en"
}

@MainActor
final class TranslateWindow {
    static let shared = TranslateWindow()
    private let model = TranslateModel()
    private var window: NSPanel?

    func translate(_ text: String, to code: String) {
        guard #available(macOS 15, *) else { return }
        model.source = text
        model.result = ""
        model.failed = false
        model.working = true
        model.target = code
        model.targetName = Translate.targets.first { $0.code == code }?.name() ?? code
        model.configToken = UUID()
        let w = window ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.contentView = NSHostingView(rootView: TranslateView(model: model) { [weak p] in p?.close() })
            return p
        }()
        window = w
        if !w.isVisible { w.center() }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

@available(macOS 15, *)
struct TranslateView: View {
    @ObservedObject var model: TranslateModel
    var close: () -> Void
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "translate").foregroundStyle(.blue)
                Text(L("Tradução para o %@", model.targetName)).font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.working { ProgressView().controlSize(.small) }
            }
            Text(model.source).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(3)
            ScrollView {
                Text(model.failed ? L("Não deu para traduzir. Confira se o idioma foi baixado em Ajustes do Sistema → Geral → Idioma e Região → Idiomas de Tradução.")
                     : (model.result.isEmpty ? L("Traduzindo…") : model.result))
                    .font(.system(size: 13)).lineSpacing(3)
                    .foregroundStyle(model.result.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .card(padding: 10)
            HStack {
                Text(L("No seu Mac, sem internet")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                PillButton(title: L("Fechar"), icon: "xmark", action: close).keyboardShortcut(.cancelAction)
                PillButton(title: L("Copiar"), icon: "doc.on.doc", primary: true) { copy(model.result) }
                    .disabled(model.result.isEmpty).keyboardShortcut("c", modifiers: .command)
            }
        }
        .padding(.horizontal, 14).padding(.top, 28).padding(.bottom, 14)
        .background(VisualEffect(material: .popover).ignoresSafeArea())
        .onAppear(perform: configure)
        .onChange(of: model.configToken) { configure() }
        .translationTask(config) { session in
            do {
                let response = try await session.translate(model.source)
                model.result = response.targetText
                model.working = false
                copy(response.targetText)
            } catch {
                model.failed = true
                model.working = false
            }
        }
    }

    private func configure() {
        // Origem detectada sozinha; uma configuração nova a cada pedido, para traduzir de novo
        let target = Locale.Language(identifier: model.target)
        if config?.target == target { config?.invalidate() } else { config = TranslationSession.Configuration(source: nil, target: target) }
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        HUD.show(icon: "translate", color: .blue, text: L("Tradução copiada"))
    }
}
