import AppKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Comandos em linguagem natural na paleta: "faz modo apresentação, muta o som e abre o Zoom".
/// O modelo do Mac escolhe, entre as ações que o Menew já tem, quais rodar e em que ordem. Você vê a lista e confirma antes.
@MainActor
enum AIAgent {
    /// Palavras que começam um pedido, nos cinco idiomas
    static let prefixes = ["fazer ", "faz ", "faça ", "do ", "please ", "mach ", "bitte ", "haz ", "hacer ", "帮我 ", "做 "]

    /// Ações que apagam ou fecham coisas ficam de fora: a IA nunca as escolhe
    private static let blocked = ["action.trash", "action.quitall", "action.quitothers", "action.forcequit", "action.update"]

    struct Step: Identifiable {
        let id = UUID()
        let title: String
        let icon: PaletteItem.Icon
        let run: () -> Void
    }

    static func item(raw: String, catalog: [PaletteItem]) -> PaletteItem? {
        guard AIFeature.agent.isOn else { return nil }
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let prefix = prefixes.first(where: { text.lowercased().hasPrefix($0) }) else { return nil }
        let request = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard request.count >= 4 else { return nil }
        if let reason = AIText.unavailableReason {
            return PaletteItem(id: "ai.agent", kind: .calc, title: L("IA do Mac indisponível"), subtitle: reason, keywords: text,
                               icon: .symbol("apple.intelligence", .gray), remember: false) {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: reason, duration: 2.5)
            }
        }
        return PaletteItem(id: "ai.agent", kind: .calc, title: L("Fazer com IA: %@", request),
                           subtitle: L("A IA monta os passos e você confirma"), keywords: text,
                           icon: .symbol("wand.and.sparkles", .pink), remember: false) {
            AIAgentWindow.shared.plan(request, catalog: catalog)
        }
    }

    /// O que o modelo pode escolher: ações, layouts de janela e perfis (id curto e título no idioma do app)
    static func choices(_ catalog: [PaletteItem]) -> [PaletteItem] {
        catalog.filter { [.action, .window, .profile].contains($0.kind) && !blocked.contains($0.id) && !$0.id.hasPrefix("ai.") }
    }

    /// Respostas do modelo → passos que existem de verdade (o resto é ignorado)
    static func resolve(_ ids: [String], catalog: [PaletteItem]) -> [Step] {
        let options = choices(catalog)
        let apps = catalog.filter { $0.kind == .app }
        var steps: [Step] = []
        for raw in ids {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.lowercased().hasPrefix("open:") {
                let name = PaletteSearch.fold(String(id.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                guard !name.isEmpty, let app = apps.first(where: { names($0).contains(name) })
                        ?? apps.first(where: { names($0).contains { $0.hasPrefix(name) } }) else { continue }
                steps.append(Step(title: L("Abrir %@", app.title), icon: app.icon, run: app.run))
            } else if let item = options.first(where: { $0.id == id || $0.id == "action." + id }) {
                steps.append(Step(title: item.title, icon: item.icon, run: item.run))
            }
        }
        return steps
    }

    /// Apps instalados cujo nome aparece no pedido
    static func mentionedApps(_ request: String, catalog: [PaletteItem]) -> [PaletteItem] {
        let text = " " + PaletteSearch.fold(request) + " "
        return catalog.filter { app in
            app.kind == .app && names(app).contains { $0.count >= 3 && text.contains(" " + $0) }
        }
    }

    /// Nome mostrado e nome do arquivo ("Notas" e "notes"), já sem acentos
    private static func names(_ app: PaletteItem) -> [String] {
        var out = [PaletteSearch.fold(app.title)]
        if case .app(let path) = app.icon {
            out.append(PaletteSearch.fold(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent))
        }
        return out
    }

    static func plan(_ request: String, catalog: [PaletteItem]) async throws -> [Step] {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            var lines = choices(catalog).map { "\($0.id.replacingOccurrences(of: "action.", with: "")): \($0.title)" }
            // Apps citados no pedido entram com o nome exato ("calculadora" → open:Calculadora)
            lines += mentionedApps(request, catalog: catalog).map { "open:\($0.title): " + L("Abrir %@", $0.title) }
            let list = lines.joined(separator: "\n")
            let session = LanguageModelSession(model: .default, instructions: """
                You turn a request into commands for a Mac utility. Pick only command ids from the list, in the order \
                they should run, at most 8. To open an app, use "open:" followed by the app name, like "open:Safari". \
                Use only commands the request asks for. If nothing fits, return an empty list.
                """)
            let answer = try await session.respond(to: "Commands:\n\(list)\n\nRequest: \(request)", generating: AgentPlan.self)
            return resolve(answer.content.commands, catalog: catalog)
        }
        #endif
        throw CancellationError()
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct AgentPlan {
    @Guide(description: "Command ids from the list, or open:AppName, in order")
    var commands: [String]
}
#endif

@MainActor
final class AIAgentModel: ObservableObject {
    @Published var request = ""
    @Published var steps: [AIAgent.Step] = []
    @Published var working = false
    @Published var failed = false
}

/// Janelinha que mostra os passos e espera você confirmar
@MainActor
final class AIAgentWindow: NSObject {
    static let shared = AIAgentWindow()
    let model = AIAgentModel()
    private var window: NSPanel?

    func plan(_ request: String, catalog: [PaletteItem]) {
        model.request = request
        model.steps = []
        model.failed = false
        model.working = true
        show()
        Task {
            do {
                model.steps = try await AIAgent.plan(request, catalog: catalog)
            } catch {
                model.failed = true
            }
            model.working = false
        }
    }

    func runAll() {
        let steps = model.steps
        close()
        // Um passo de cada vez: abrir app e mudar ajustes levam um instante
        for (i, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.5) { step.run() }
        }
    }

    func close() { window?.orderOut(nil) }

    private func show() {
        let w = window ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
                            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.contentView = NSHostingView(rootView: AIAgentView(model: model))
            return p
        }()
        window = w
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct AIAgentView: View {
    @ObservedObject var model: AIAgentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.sparkles").foregroundStyle(.pink)
                Text(model.request).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer()
                if model.working { ProgressView().controlSize(.small) }
            }
            VStack(alignment: .leading, spacing: 0) {
                if model.working {
                    Text(L("Montando os passos…")).font(.system(size: 12.5)).foregroundStyle(.secondary).padding(10)
                } else if model.failed {
                    Text(L("A IA não conseguiu responder")).font(.system(size: 12.5)).foregroundStyle(.secondary).padding(10)
                } else if model.steps.isEmpty {
                    Text(L("Não achei nada que o Menew saiba fazer nesse pedido. Tente com outras palavras.")).font(.system(size: 12.5))
                        .foregroundStyle(.secondary).padding(10)
                } else {
                    ForEach(Array(model.steps.enumerated()), id: \.element.id) { i, step in
                        if i > 0 { RowDivider() }
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).frame(width: 14)
                            PaletteIcon(icon: step.icon).frame(width: 20, height: 20)
                            Text(step.title).font(.system(size: 12.5))
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 4)
            Spacer(minLength: 0)
            HStack {
                Text(L("No seu Mac, sem internet")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                PillButton(title: L("Cancelar"), icon: "xmark") { AIAgentWindow.shared.close() }
                    .keyboardShortcut(.cancelAction)
                PillButton(title: L("Fazer"), icon: "play.fill", primary: true) { AIAgentWindow.shared.runAll() }
                    .disabled(model.working || model.steps.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14).padding(.top, 28).padding(.bottom, 14)
        .frame(width: 440, height: 320)
        .background(VisualEffect(material: .popover).ignoresSafeArea())
    }
}
