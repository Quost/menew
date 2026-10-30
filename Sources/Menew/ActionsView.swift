import SwiftUI

// MARK: Ações

/// Em cima, controles que ligam e desligam (sempre mostrando o estado atual do Mac);
/// embaixo, ações de um toque, cada uma dizendo o que faz.
struct ActionsView: View {
    @ObservedObject var tb: Toolbox
    @ObservedObject var cleaning: CleaningController
    @ObservedObject var displays: DisplayController
    @ObservedObject var profiles = ProfileStore.shared
    @State private var editingProfile: UUID?
    @ObservedObject var automations = AutomationStore.shared
    @State private var editingAutomation: UUID?
    let clipboard: ClipboardManager
    var openCleaner: () -> Void

    init(tb: Toolbox, clipboard: ClipboardManager, openCleaner: @escaping () -> Void) {
        self.tb = tb
        self.cleaning = tb.cleaning
        self.displays = tb.displays
        self.clipboard = clipboard
        self.openCleaner = openCleaner
    }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        if let id = editingProfile, let p = profiles.profile(id) {
            ProfileEditor(store: profiles, tb: tb, profile: p) { editingProfile = nil }
                .id(id)
        } else if let id = editingAutomation, let r = automations.rule(id) {
            AutomationEditor(store: automations, rule: r) { editingAutomation = nil }
                .id(id)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !displays.screens.isEmpty {
                    section(L("Brilho")) {
                        VStack(spacing: 0) {
                            ForEach(Array(displays.screens.enumerated()), id: \.element.id) { i, screen in
                                if i > 0 { Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52) }
                                BrightnessRow(screen: screen) { displays.set($0, for: screen.id) }
                            }
                        }
                        .padding(.vertical, 4)
                        .glass()
                    }
                }

                section(L("Foco")) { FocusCard() }

                section(L("Controles")) {
                    VStack(spacing: 0) {
                        ControlRow(icon: tb.micMuted ? "mic.slash.fill" : "mic.fill", color: .red,
                                   title: L("Mutar microfone"), state: tb.micMuted ? L("Mudo") : L("Ligado"),
                                   help: L("Silencia o microfone em qualquer app, bom para reuniões. Também pelo atalho %@.", micShortcut),
                                   isOn: Binding(get: { tb.micMuted }, set: { _ in tb.toggleMic() })) {
                            Text(micShortcut).font(.system(size: 10.5, weight: .medium, design: .rounded))
                        }
                        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
                        ControlRow(icon: tb.soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", color: .pink,
                                   title: L("Mutar som"), state: tb.soundMuted ? L("Mudo") : L("Ligado"),
                                   help: L("Silencia a saída de som atual do Mac."),
                                   isOn: Binding(get: { tb.soundMuted }, set: { _ in tb.toggleSound() }))
                        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
                        ControlRow(icon: tb.darkMode ? "moon.fill" : "sun.max.fill", color: tb.darkMode ? .indigo : .orange,
                                   title: L("Modo escuro"), state: tb.darkMode ? L("Ligado") : L("Desligado"),
                                   help: L("Troca a aparência de todo o macOS entre claro e escuro."),
                                   isOn: Binding(get: { tb.darkMode }, set: { _ in tb.toggleDarkMode() }))
                        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
                        ControlRow(icon: "cup.and.saucer.fill", color: .orange, title: L("Manter acordado"),
                                   state: awakeState, help: L("Impede que a tela apague e o Mac durma."),
                                   isOn: Binding(get: { tb.keepAwake }, set: { tb.setKeepAwake($0) })) {
                            Menu {
                                ForEach([30, 60, 120, 240], id: \.self) { m in
                                    Button(m < 60 ? L("%d minutos", m) : (m == 60 ? L("1 hora") : L("%d horas", m / 60))) {
                                        tb.setKeepAwake(true, minutes: m)
                                    }
                                }
                                Menu(L("Até um horário")) {
                                    ForEach(Self.nextHours(), id: \.self) { d in
                                        Button(d.formatted(.dateTime.hour().minute().locale(L10n.locale))) { tb.keepAwake(until: d) }
                                    }
                                }
                                Menu(L("Enquanto um app estiver aberto")) {
                                    ForEach(Self.runningApps(), id: \.processIdentifier) { app in
                                        Button(app.localizedName ?? "") { tb.keepAwake(while: app) }
                                    }
                                }
                                Divider()
                                Button(L("Até eu desligar")) { tb.setKeepAwake(true) }
                            } label: {
                                Image(systemName: "timer").font(.system(size: 12, weight: .semibold))
                            }
                            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                            .help(L("Manter acordado por um tempo"))
                        }
                        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
                        ControlRow(icon: tb.hiddenFiles ? "eye.fill" : "eye.slash.fill", color: .blue,
                                   title: L("Arquivos ocultos"), state: tb.hiddenFiles ? L("Aparecem no Finder") : L("Escondidos no Finder"),
                                   help: L("Mostra arquivos que começam com ponto, como .git e .env. O Finder reinicia."),
                                   isOn: Binding(get: { tb.hiddenFiles }, set: { _ in tb.toggleHiddenFiles() }))
                        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
                        ControlRow(icon: "menubar.dock.rectangle", color: .teal,
                                   title: L("Ícones da mesa"), state: tb.desktopIconsHidden ? L("Escondidos") : L("Aparecem"),
                                   help: L("Esconde tudo da mesa, bom para gravar a tela ou apresentar. Os arquivos continuam lá."),
                                   isOn: Binding(get: { !tb.desktopIconsHidden }, set: { _ in tb.toggleDesktopIcons() }))
                        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
                        ControlRow(icon: "dock.rectangle", color: .gray,
                                   title: L("Esconder o Dock"), state: tb.dockAutohide ? L("Aparece ao levar o mouse") : L("Sempre visível"),
                                   help: L("Esconde o Dock automaticamente e libera espaço na tela."),
                                   isOn: Binding(get: { tb.dockAutohide }, set: { _ in tb.toggleDockAutohide() }))
                    }
                    .padding(.vertical, 4)
                    .glass()
                }

                section(L("Janelas")) {
                    VStack(spacing: 6) {
                        GlassGroup(spacing: 6) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                                ForEach(WindowLayout.allCases.filter { $0 != .nextDisplay || NSScreen.screens.count > 1 || isSnapshot }) { l in
                                    Button { WindowManager.shared.apply(l, fromMenu: true) } label: {
                                        LayoutIcon(layout: l)
                                            .frame(maxWidth: .infinity, minHeight: 34)
                                            .contentShape(Rectangle())
                                            .glass(interactive: true)
                                    }
                                    .buttonStyle(.plain)
                                    .help("\(l.title)  \(l.shortcutDisplay)")
                                    .accessibilityLabel(l.title)
                                }
                            }
                        }
                        Text(L("Move a janela do app que estava na frente. Atalhos: ⌃⌥ + setas, U I J K, D F G, E T, ↩ e C."))
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary).padding(.leading, 4)
                    }
                }

                section(L("Apps")) { AppControlSection() }

                section(L("Perfis")) {
                    ProfilesSection(store: profiles, tb: tb, editing: $editingProfile)
                }

                section(L("Automações")) {
                    AutomationsSection(store: automations, editing: $editingAutomation)
                }

                section(L("Limpeza")) {
                    GlassGroup {
                        LazyVGrid(columns: cols, spacing: 8) {
                            ActionTile(icon: "sparkles", color: .blue, title: L("Liberar espaço"), subtitle: L("caches e lixo"),
                                       help: L("Encontra caches, logs e arquivos grandes. Você revisa antes de apagar."), action: openCleaner)
                            ActionTile(icon: "keyboard", color: .teal, title: L("Limpar teclado"),
                                       subtitle: cleaning.keyboardLocked ? L("travado") : L("trava por 2 min"),
                                       help: L("Bloqueia todas as teclas por 2 minutos para você limpar. Destrava com um clique."),
                                       on: cleaning.keyboardLocked) {
                                if !cleaning.lockKeyboard() { tb.show(L("Libere o Menew em Acessibilidade")) }
                            }
                            ActionTile(icon: "sparkles.tv", color: .cyan, title: L("Limpar tela"), subtitle: L("tela preta"),
                                       help: L("Deixa todas as telas pretas para ver manchas. Dois cliques para sair.")) {
                                cleaning.blackScreen()
                            }
                        }
                    }
                }

                section(L("Atalhos")) {
                    GlassGroup {
                        LazyVGrid(columns: cols, spacing: 8) {
                            ActionTile(icon: "camera.viewfinder", color: .pink, title: L("Capturar tela"), subtitle: L("anotar e fixar"),
                                       help: L("Selecione uma área (espaço captura uma janela). Depois anote com setas, texto e borrão, copie, salve ou fixe na tela.")) {
                                ScreenCapture.area()
                            }
                            ActionTile(icon: "eyedropper.halffull", color: Theme.violet, title: L("Conta-gotas"), subtitle: L("copia o hex"),
                                       help: L("Clique em qualquer ponto da tela para copiar a cor em hexadecimal.")) {
                                tb.pickColor(clipboard: clipboard)
                            }
                            ActionTile(icon: "textformat", color: .brown, title: L("Limpar formatação"), subtitle: L("do texto copiado"),
                                       help: L("Tira fonte, cor e links do texto copiado. Cole como texto simples.")) {
                                tb.plainTextClipboard()
                            }
                            ActionTile(icon: "lock.fill", color: .gray, title: L("Bloquear tela"), subtitle: L("pede a senha"),
                                       help: L("Apaga a tela na hora. Para voltar, use Touch ID ou sua senha.")) { tb.lockScreen() }
                            ActionTile(icon: "eject.fill", color: .mint, title: L("Ejetar discos"),
                                       subtitle: tb.ejectableCount == 0 ? L("nenhum conectado") : L("%d conectado(s)", tb.ejectableCount),
                                       help: L("Ejeta com segurança todos os discos externos e pendrives."),
                                       disabled: tb.ejectableCount == 0) { tb.ejectAll() }
                            ActionTile(icon: "trash", color: .red, title: L("Esvaziar lixeira"), subtitle: L("pede confirmação"),
                                       help: L("Apaga para sempre o que está na Lixeira. Pergunta antes.")) { tb.emptyTrash() }
                        }
                    }
                }

                HStack(spacing: 8) {
                    AppPill(icon: "chart.bar.xaxis", title: L("Monitor de Atividade")) {
                        tb.open("/System/Applications/Utilities/Activity Monitor.app")
                    }
                    AppPill(icon: "terminal.fill", title: L("Terminal")) {
                        tb.open("/System/Applications/Utilities/Terminal.app")
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .noLiquidGlass()
        .scrollIndicators(.never)
        .onAppear { tb.refresh() }
    }

    /// As próximas 8 horas cheias (a primeira com pelo menos 30 min de folga)
    static func nextHours() -> [Date] {
        let cal = Calendar.current
        let start = cal.nextDate(after: Date().addingTimeInterval(30 * 60), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date()
        return (0..<8).compactMap { cal.date(byAdding: .hour, value: $0, to: start) }
    }

    static func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private var isSnapshot: Bool { CommandLine.arguments.contains("--snapshot") }

    private var micShortcut: String { Shortcut.load(HotKeyCenter.micKey, default: .micDefault).display }

    private var awakeState: String {
        guard tb.keepAwake else { return L("Desligado") }
        if let app = tb.awakeApp { return L("Enquanto %@ estiver aberto", app.localizedName ?? "") }
        guard let until = tb.awakeUntil else { return L("Até você desligar") }
        return L("Até %@", until.formatted(.dateTime.hour().minute().locale(L10n.locale)))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            content()
        }
    }
}

/// Uma tela com o slider de brilho; monitores sem DDC dizem por que não dá
struct BrightnessRow: View {
    let screen: ScreenInfo
    let onChange: (Double) -> Void
    @State private var value: Double?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: screen.builtin ? "laptopcomputer" : "display")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.yellow.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(screen.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if screen.kind == .software {
                        Text(L("por software")).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                            .help(L("Este monitor não aceita ajuste pelo cabo (DDC/CI). O Menew escurece a imagem, sem mexer na luz do monitor."))
                    }
                    if screen.kind != .unsupported {
                        Text(Fmt.pct(value ?? screen.brightness)).font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if screen.kind == .unsupported {
                    Text(L("Este monitor não aceita ajuste de brilho pelo Mac (DDC/CI)."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.min").font(.system(size: 10)).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { value ?? screen.brightness },
                                              set: { value = $0; onChange($0) }), in: 0...1)
                            .controlSize(.small).tint(.yellow)
                        Image(systemName: "sun.max.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .onChange(of: screen.brightness) { _, _ in value = nil }
    }
}

/// Linha com ícone, nome, estado atual por extenso e um interruptor
struct ControlRow<Extra: View>: View {
    let icon: String
    let color: Color
    let title: String
    let state: String
    let help: String
    @Binding var isOn: Bool
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isOn ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.15))))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(state).font(.system(size: 11)).foregroundStyle(isOn ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 6)
            extra.foregroundStyle(.secondary)
            Toggle(title, isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(color)
                .accessibilityValue(state)
                .accessibilityHint(help)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .help(help)
        .animation(.spring(duration: 0.3), value: isOn)
    }
}

extension ControlRow where Extra == EmptyView {
    init(icon: String, color: Color, title: String, state: String, help: String, isOn: Binding<Bool>) {
        self.init(icon: icon, color: color, title: title, state: state, help: help, isOn: isOn) { EmptyView() }
    }
}

/// Ação de um toque: ícone, nome e o que acontece, em vidro
struct ActionTile: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    var help: String = ""
    var on = false
    var disabled = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(color.gradient))
                    .shadow(color: color.opacity(0.35), radius: hover ? 6 : 3, y: 2)
                    .scaleEffect(hover && !disabled ? 1.06 : 1)
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(on ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 92)
            .contentShape(Rectangle())
            .glass(tint: on ? color.opacity(0.25) : nil, interactive: !disabled)
        }
        .buttonStyle(.plain)
        .accessibilityHint(help)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hover = $0 }
        .help(help)
        .animation(.spring(duration: 0.25), value: hover)
        .animation(.spring(duration: 0.25), value: on)
    }
}

struct AppPill: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
            .glass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .help(L("Abrir %@", title))
    }
}
