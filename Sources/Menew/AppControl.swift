import AppKit
import SwiftUI

/// Fechar, esconder e forçar o encerramento de apps. Fechar é um pedido normal: o app pergunta se há algo sem salvar.
/// Finder, o Menew e os apps em "Nunca fechar" ficam sempre de fora.
@MainActor
enum AppControl {
    static let keepKey = "appControlKeep"

    static var kept: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: keepKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: keepKey) }
    }

    /// Apps com janela no Dock, sem o Finder e o Menew
    static var running: [NSRunningApplication] {
        let me = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != me && $0.bundleIdentifier != "com.apple.finder" && !$0.isTerminated
        }
        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    /// O app que estava na frente antes de abrir o Menew
    static var front: NSRunningApplication? {
        let f = NSWorkspace.shared.frontmostApplication
        return f?.bundleIdentifier == Bundle.main.bundleIdentifier ? WindowManager.shared.previousApp : f
    }

    /// O que "fechar" alcançaria, deixando de fora `sparing` e os da lista "Nunca fechar"
    static func targets(sparing: Set<String> = []) -> [NSRunningApplication] {
        let keep = kept.union(sparing)
        return running.filter { !keep.contains($0.bundleIdentifier ?? "") }
    }

    @discardableResult
    static func quitAll(sparing: Set<String> = []) -> Int {
        let list = targets(sparing: sparing)
        for app in list { app.terminate() }
        return list.count
    }

    @discardableResult
    static func quitOthers() -> Int {
        quitAll(sparing: Set([front?.bundleIdentifier].compactMap { $0 }))
    }

    static func hideOthers() {
        let keep = front?.bundleIdentifier
        for app in running where app.bundleIdentifier != keep { app.hide() }
        front?.activate()
    }

    static func forceQuit(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "?"
        if app.forceTerminate() {
            HUD.show(icon: "xmark.octagon.fill", color: .red, text: L("%@ encerrado", name))
        } else {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para encerrar %@", name))
        }
    }

    static func quitAllWithNotice(others: Bool) {
        let n = others ? quitOthers() : quitAll()
        HUD.show(icon: "xmark.circle.fill", color: .red, text: n == 1 ? L("Fechando 1 app") : L("Fechando %d apps", n))
    }
}

/// Seção "Apps" na aba Ações
struct AppControlSection: View {
    @State private var confirmAll = false
    @State private var confirmOthers = false
    @State private var keep = AppControl.kept
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 6) {
            GlassGroup {
                LazyVGrid(columns: cols, spacing: 8) {
                    ActionTile(icon: "xmark.circle.fill", color: .red, title: L("Fechar todos"), subtitle: count(AppControl.targets().count),
                               help: L("Pede para todos os apps fecharem. Quem tiver algo sem salvar pergunta antes.")) { confirmAll = true }
                    ActionTile(icon: "rectangle.portrait.and.arrow.right.fill", color: .orange, title: L("Fechar os outros"),
                               subtitle: AppControl.front?.localizedName.map { L("menos %@", $0) },
                               help: L("Fecha tudo, menos o app que estava na frente.")) { confirmOthers = true }
                    ActionTile(icon: "eye.slash.fill", color: .gray, title: L("Esconder os outros"), subtitle: L("sem fechar"),
                               help: L("Esconde as janelas dos outros apps, sem fechar nada.")) { AppControl.hideOthers() }
                }
            }
            HStack(spacing: 14) {
                Menu {
                    ForEach(AppControl.running, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? "?") { AppControl.forceQuit(app) }
                    }
                } label: {
                    Label(L("Forçar encerramento"), systemImage: "xmark.octagon").font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                .help(L("Para um app travado. Ele fecha na hora, sem salvar."))

                Menu {
                    ForEach(AppControl.running, id: \.processIdentifier) { app in
                        if let id = app.bundleIdentifier {
                            Toggle(app.localizedName ?? id, isOn: Binding(get: { keep.contains(id) }, set: { on in
                                if on { keep.insert(id) } else { keep.remove(id) }
                                AppControl.kept = keep
                            }))
                        }
                    }
                } label: {
                    Label(keep.isEmpty ? L("Nunca fechar…") : L("Nunca fechar: %d", keep.count), systemImage: "lock")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                .help(L("Apps que “Fechar todos”, os perfis e as automações nunca fecham"))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
        }
        .confirmationDialog(L("Fechar todos os apps?"), isPresented: $confirmAll) {
            Button(L("Fechar todos"), role: .destructive) { AppControl.quitAllWithNotice(others: false) }
        } message: { Text(L("Quem tiver algo sem salvar pergunta antes.")) }
        .confirmationDialog(L("Fechar os outros apps?"), isPresented: $confirmOthers) {
            Button(L("Fechar os outros"), role: .destructive) { AppControl.quitAllWithNotice(others: true) }
        } message: { Text(L("Quem tiver algo sem salvar pergunta antes.")) }
    }

    private func count(_ n: Int) -> String { n == 1 ? L("1 app") : L("%d apps", n) }
}
