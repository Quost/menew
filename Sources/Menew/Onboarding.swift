import AppKit
import ApplicationServices
import SwiftUI

// MARK: Módulos opcionais

/// Partes do app que podem ser desligadas. O Sistema fica sempre ligado.
enum Module: String, CaseIterable {
    case clipboard, actions, notes

    var key: String { "module_\(rawValue)" }

    /// Ligado por padrão
    var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    var tab: Tab {
        switch self {
        case .clipboard: .clipboard
        case .actions: .actions
        case .notes: .notes
        }
    }

    var title: String {
        switch self {
        case .clipboard: L("Histórico do clipboard")
        case .actions: L("Ações rápidas")
        case .notes: L("Notas")
        }
    }

    var detail: String {
        switch self {
        case .clipboard: L("Guarda o que você copia. Desligado, o Menew nem lê a área de transferência.")
        case .actions: L("Modo escuro, manter acordado, print, conta-gotas e mais.")
        case .notes: L("Notas rápidas com #tags, checklists e Touch ID.")
        }
    }

    var icon: String { tab.icon }

    var color: Color {
        switch self {
        case .clipboard: .blue
        case .actions: .orange
        case .notes: .yellow
        }
    }
}

/// Linha com ícone colorido, nome, explicação e interruptor de um módulo
struct ModuleToggle: View {
    let module: Module
    @AppStorage private var on: Bool

    init(_ module: Module) {
        self.module = module
        _on = AppStorage(wrappedValue: true, module.key)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Color.white : module.color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(on ? AnyShapeStyle(module.color.gradient) : AnyShapeStyle(module.color.opacity(0.15))))
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title).font(.system(size: 12.5, weight: .semibold))
                Text(module.detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $on).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(module.color)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { on.toggle() }
        .animation(.spring(duration: 0.3), value: on)
    }
}

// MARK: Boas-vindas

/// Janela mostrada na primeira vez que o Menew abre (e de novo pelos Ajustes)
@MainActor
final class WelcomeController: NSObject, NSWindowDelegate {
    static let doneKey = "onboarded"
    private var window: NSWindow?
    private let monitor: SystemMonitor
    var onOpenMenu: () -> Void = {}

    init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    /// Só para quem acabou de instalar: quem já tem histórico ou notas não vê a apresentação
    func showIfNeeded(existingUser: Bool) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.doneKey) else { return }
        if existingUser { defaults.set(true, forKey: Self.doneKey); return }
        show()
    }

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = WelcomeView(monitor: monitor) { [weak self] openMenu in
            self?.finish(openMenu: openMenu)
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        let host = NSHostingView(rootView: view)
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        w.contentView = effect
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(openMenu: Bool) {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window?.close()
        if openMenu { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.onOpenMenu() } }
    }

    /// Fechar no X também conta como visto: a apresentação não volta sozinha
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window = nil
    }
}

struct WelcomeView: View {
    @ObservedObject var monitor: SystemMonitor
    var onFinish: (_ openMenu: Bool) -> Void
    @State var step = 0
    @AppStorage(MenuBarItem.key) private var menuBarItems = "cpu,ram"
    @AppStorage(Module.clipboard.key) private var clipboardOn = true
    @State private var axTrusted = AXIsProcessTrusted()
    @AppStorage("language") private var language = "auto"

    private let steps = 5
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: hello
                case 1: modules
                case 2: menuBar
                case 3: permission
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 28).padding(.top, 44)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            footer
        }
        .frame(width: 480, height: 560)
        .background(Theme.popoverFill)
        .id(language)
        .onReceive(poll) { _ in if step == 3 { axTrusted = AXIsProcessTrusted() } }
    }

    // Passo 1: o que é e onde fica
    private var hello: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                .shadow(color: Theme.violet.opacity(0.3), radius: 12, y: 4)
            VStack(spacing: 6) {
                Text(L("Bem-vindo ao Menew")).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(L("Ele mora na barra de menus, ao lado do relógio. Clique no ícone para abrir."))
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                feature("gauge.with.dots.needle.67percent", Theme.cpu, L("Sistema num relance"),
                        L("CPU, memória, bateria, disco e internet."))
                RowDivider(inset: 52)
                feature("doc.on.clipboard", .blue, L("Tudo o que você copia"),
                        L("Busque e cole de novo com ⌘⇧V, de qualquer app."))
                RowDivider(inset: 52)
                feature("bolt.fill", .orange, L("Atalhos do dia a dia"),
                        L("Modo escuro, manter acordado, print, limpar espaço."))
            }
            .padding(.vertical, 3)
            .glass()
        }
    }

    private func feature(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Circle().fill(color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    // Passo 2: módulos
    private var modules: some View {
        VStack(alignment: .leading, spacing: 16) {
            title(L("Escolha o que usar"), L("Desligue o que você não precisa: o menu fica mais simples. Dá para mudar depois em Ajustes."))
            VStack(spacing: 0) {
                ForEach(Array(Module.allCases.enumerated()), id: \.element) { i, m in
                    if i > 0 { RowDivider(inset: 52) }
                    ModuleToggle(m)
                }
            }
            .padding(.vertical, 3)
            .glass()
        }
    }

    // Passo 3: barra de menus
    private var menuBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            title(L("Sua barra de menus"), L("Escolha o que aparece ao lado do ícone. A prévia mostra os números de agora."))
            MenuBarItemsPicker(selection: $menuBarItems, monitor: monitor)
                .glass()
        }
    }

    // Passo 4: Acessibilidade
    private var permission: some View {
        VStack(alignment: .leading, spacing: 16) {
            title(L("Uma permissão"), L("A Acessibilidade deixa o Menew colar direto no app em que você estava e travar o teclado na limpeza. Ele não guarda nada do que você digita."))
            HStack(spacing: 12) {
                Image(systemName: axTrusted ? "checkmark.seal.fill" : "hand.raised.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(axTrusted ? .green : Theme.indigo)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Acessibilidade")).font(.system(size: 13, weight: .semibold))
                    Text(axTrusted ? L("Permitido") : L("Abre os Ajustes do Sistema. Ative o Menew na lista."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if !axTrusted {
                    PillButton(title: L("Permitir"), primary: true) { ClipboardManager.requestAccessibility() }
                }
            }
            .padding(14)
            .glass()
            .animation(.spring(duration: 0.3), value: axTrusted)
            Text(L("Prefere depois? Tudo bem: o Menew pede de novo quando precisar."))
                .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 4)
        }
    }

    // Passo 5: atalhos e pronto
    private var done: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.green.gradient).frame(width: 72, height: 72)
                Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            }
            .shadow(color: .green.opacity(0.3), radius: 12, y: 4)
            VStack(spacing: 6) {
                Text(L("Tudo pronto")).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(L("Dois atalhos para lembrar:")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                shortcutRow(Shortcut.load(HotKeyCenter.menuKey, default: .menuDefault).display, L("Abrir este menu"))
                if clipboardOn {
                    RowDivider()
                    shortcutRow(Shortcut.load(HotKeyCenter.clipboardKey, default: .clipboardDefault).display, L("Histórico do clipboard"))
                }
            }
            .padding(.vertical, 3)
            .glass()
            Text(L("Clique com o botão direito no ícone para mais opções."))
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    private func shortcutRow(_ keys: String, _ label: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5))
            Spacer()
            Text(keys).font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(sub).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                PillButton(title: L("Voltar")) { go(step - 1) }
            } else {
                Button(L("Pular")) { onFinish(false) }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule().fill(i == step ? AnyShapeStyle(Theme.indigo) : AnyShapeStyle(Color.primary.opacity(0.18)))
                        .frame(width: i == step ? 16 : 6, height: 6)
                }
            }
            .animation(.spring(duration: 0.3), value: step)
            Spacer()
            if step < steps - 1 {
                PillButton(title: L("Continuar"), icon: "arrow.right", primary: true) { go(step + 1) }
            } else {
                PillButton(title: L("Abrir o Menew"), primary: true) { onFinish(true) }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    private func go(_ s: Int) {
        withAnimation(.spring(duration: 0.35)) { step = s }
    }
}

extension Notification.Name {
    static let showWelcome = Notification.Name("MenewShowWelcome")
    static let closeMenu = Notification.Name("MenewCloseMenu")
}
