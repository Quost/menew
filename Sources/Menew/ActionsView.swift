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
    @ObservedObject var presentation = PresentationMode.shared
    @State private var editingAutomation: UUID?
    /// Seções de "Mais ações" abertas (as outras ficam recolhidas, só com o resumo)
    @AppStorage("actionsOpen") private var openRaw = ""
    let clipboard: ClipboardManager
    var openCleaner: () -> Void

    /// false = página de um grupo só, sem "voltar" (na janela Menew)
    var showsBack = true

    init(tb: Toolbox, clipboard: ClipboardManager, group: ActionGroup? = nil, showsBack: Bool = true, openCleaner: @escaping () -> Void) {
        _group = State(initialValue: group)
        self.showsBack = showsBack
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

    @State private var group: ActionGroup?

    /// Os 6 grupos da aba: cada um abre uma página só com o que é dele
    enum ActionGroup: String, CaseIterable, Identifiable {
        case capture, windows, sound, files, ai, system
        var id: String { rawValue }
        var title: String {
            switch self {
            case .capture: L("Tela e captura")
            case .windows: L("Janelas e telas")
            case .sound: L("Som e foco")
            case .files: L("Arquivos e iPhone")
            case .ai: L("IA no Mac")
            case .system: L("Sistema e limpeza")
            }
        }
        var detail: String {
            switch self {
            case .capture: L("Capturar, gravar, rolagem, texto da tela, conta-gotas")
            case .windows: L("Brilho, organizar janelas, modo escuro, Dock, apresentação")
            case .sound: L("Microfone, saída de som, foco, legendas ao vivo")
            case .files: L("Estante, foto ou scan do iPhone, discos, lixeira")
            case .ai: L("Perguntar à tela, perguntar à IA, comandos")
            case .system: L("Liberar espaço, desinstalar, apps, perfis, automações")
            }
        }
        var icon: String {
            switch self {
            case .capture: "camera.viewfinder"
            case .windows: "macwindow.on.rectangle"
            case .sound: "speaker.wave.2.fill"
            case .files: "doc.on.doc.fill"
            case .ai: "apple.intelligence"
            case .system: "gearshape.2.fill"
            }
        }
        var color: Color {
            switch self {
            case .capture: .pink
            case .windows: .cyan
            case .sound: .red
            case .files: .blue
            case .ai: Theme.violet
            case .system: .teal
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let group {
                    groupPage(group)
                } else {
                    home
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .noLiquidGlass()
        .scrollIndicators(.never)
        .onAppear { tb.refresh() }
    }

    // Favoritos e os grupos; a busca é a própria paleta
    @ViewBuilder private var home: some View {
        Button { (NSApp.delegate as? AppDelegate)?.palette.show() } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(L("Buscar ação, ex.: brilho, pdf, desinstalar")).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        FavoritesSection(tb: tb, clipboard: clipboard, openCleaner: openCleaner)

        VStack(spacing: 0) {
            ForEach(Array(ActionGroup.allCases.enumerated()), id: \.element) { i, g in
                if i > 0 { Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52) }
                Button { withAnimation(.snappy) { group = g } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: g.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(g.color.gradient))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.title).font(.system(size: 13, weight: .semibold))
                            Text(g.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .glass()

        Text(L("Tudo aqui também abre pela paleta: digite o nome e ↩."))
            .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 4)
    }

    @ViewBuilder private func groupPage(_ g: ActionGroup) -> some View {
        if showsBack {
        HStack(spacing: 8) {
            IconButton(icon: "chevron.left", help: L("Voltar")) { withAnimation(.snappy) { group = nil } }
            Image(systemName: g.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(g.color.gradient))
            Text(g.title).font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        }
        switch g {
        case .capture:
            tiles { captureTile; memoryCaptureTile; recordTile; scrollTile; ocrTile; qrTile; colorTile }
        case .windows:
            if !displays.screens.isEmpty {
                    section(L("Brilho"), collapsible: false) {
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
            section(L("Janelas"), collapsible: false) { windowsGrid }
            controls { darkRow; divider; desktopRow; divider; dockRow; divider; presentRow }
            tiles { blackScreenTile; lockTile }
        case .sound:
            controls { micRow; divider; soundRow }
            section(L("Som"), collapsible: false) { AudioSection() }
            section(L("Foco"), collapsible: false) { FocusCard() }
            tiles { recordAudioTile; captionsTile }
        case .files:
            tiles { organizeTile; iphoneTile; shelfTile; plainTile; ejectTile; trashTile }
            controls { hiddenRow }
        case .ai:
            tiles {
                memoryTile
                if AIFeature.screenAsk.isOn { screenAskTile }
                if AIFeature.ask.isOn { askTile }
                if AIFeature.agent.isOn { agentTile }
                captionsTile
                aiSettingsTile
            }
        case .system:
            tiles { freeSpaceTile; uninstallTile; loginTile; scriptsTile; keyboardTile; activityTile }
            controls { awakeRow }
            section(L("Apps"), collapsible: false) { AppControlSection() }
            section(L("Perfis"), collapsible: false) { ProfilesSection(store: profiles, tb: tb, editing: $editingProfile) }
            section(L("Automações"), collapsible: false) { AutomationsSection(store: automations, editing: $editingAutomation) }
        }
    }

    // MARK: Peças

    private func tiles<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        GlassGroup { LazyVGrid(columns: cols, spacing: 8) { content() } }
    }

    private func controls<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }.padding(.vertical, 4).glass()
    }

    private var divider: some View { Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52) }

    private var micRow: some View {
        ControlRow(icon: tb.micMuted ? "mic.slash.fill" : "mic.fill", color: .red,
                   title: L("Mutar microfone"), state: tb.micMuted ? L("Mudo") : L("Ligado"),
                   help: L("Silencia o microfone em qualquer app, bom para reuniões. Também pelo atalho %@.", micShortcut),
                   isOn: Binding(get: { tb.micMuted }, set: { _ in tb.toggleMic() })) {
            Text(micShortcut).font(.system(size: 10.5, weight: .medium, design: .rounded))
        }
    }

    private var soundRow: some View {
        ControlRow(icon: tb.soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", color: .pink,
                   title: L("Mutar som"), state: tb.soundMuted ? L("Mudo") : L("Ligado"),
                   help: L("Silencia a saída de som atual do Mac."),
                   isOn: Binding(get: { tb.soundMuted }, set: { _ in tb.toggleSound() }))
    }

    private var darkRow: some View {
        ControlRow(icon: tb.darkMode ? "moon.fill" : "sun.max.fill", color: tb.darkMode ? .indigo : .orange,
                   title: L("Modo escuro"), state: tb.darkMode ? L("Ligado") : L("Desligado"),
                   help: L("Troca a aparência de todo o macOS entre claro e escuro."),
                   isOn: Binding(get: { tb.darkMode }, set: { _ in tb.toggleDarkMode() }))
    }

    private var awakeRow: some View {
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
    }

    private var hiddenRow: some View {
        ControlRow(icon: tb.hiddenFiles ? "eye.fill" : "eye.slash.fill", color: .blue,
                   title: L("Arquivos ocultos"), state: tb.hiddenFiles ? L("Aparecem no Finder") : L("Escondidos no Finder"),
                   help: L("Mostra arquivos que começam com ponto, como .git e .env. O Finder reinicia."),
                   isOn: Binding(get: { tb.hiddenFiles }, set: { _ in tb.toggleHiddenFiles() }))
    }

    private var desktopRow: some View {
        ControlRow(icon: "menubar.dock.rectangle", color: .teal,
                   title: L("Ícones da mesa"), state: tb.desktopIconsHidden ? L("Escondidos") : L("Aparecem"),
                   help: L("Esconde tudo da mesa, bom para gravar a tela ou apresentar. Os arquivos continuam lá."),
                   isOn: Binding(get: { !tb.desktopIconsHidden }, set: { _ in tb.toggleDesktopIcons() }))
    }

    private var dockRow: some View {
        ControlRow(icon: "dock.rectangle", color: .gray,
                   title: L("Esconder o Dock"), state: tb.dockAutohide ? L("Aparece ao levar o mouse") : L("Sempre visível"),
                   help: L("Esconde o Dock automaticamente e libera espaço na tela."),
                   isOn: Binding(get: { tb.dockAutohide }, set: { _ in tb.toggleDockAutohide() }))
    }

    private var presentRow: some View {
        ControlRow(icon: "play.rectangle.fill", color: .green,
                   title: L("Modo apresentação"), state: presentation.isOn ? L("Ligado") : L("Desligado"),
                   help: L("Antes de apresentar ou compartilhar a tela: esconde os ícones da mesa, mantém o Mac acordado, pausa o clipboard e deixa só o ícone na barra de menus. Desligar desfaz tudo."),
                   isOn: Binding(get: { presentation.isOn }, set: { presentation.set($0) }))
    }

    private var windowsGrid: some View {
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

    private var captureTile: some View {
        ActionTile(icon: "camera.viewfinder", color: .pink, title: L("Capturar tela"), subtitle: L("anotar e fixar"),
                   help: L("Selecione uma área (espaço captura uma janela). Depois anote com setas, texto e borrão, copie, salve ou fixe na tela.")) {
            ScreenCapture.area()
        }
    }
    private var memoryTile: some View {
        ActionTile(icon: "brain.head.profile", color: .pink, title: L("Memória"), subtitle: L("guarde e ache"),
                   help: L("Guarde o que está na tela com %@ e ache depois pela busca. Clique para abrir a memória.",
                           Shortcut.load(MemoryStore.shortcutKey, default: .memoryDefault).display)) {
            MemoryWindow.shared.show()
        }
    }
    private var memoryCaptureTile: some View {
        ActionTile(icon: "plus.viewfinder", color: .pink, title: L("Guardar na memória"),
                   subtitle: Shortcut.load(MemoryStore.shortcutKey, default: .memoryDefault).display,
                   help: L("Captura uma área ou janela com o texto e a origem")) {
            MemoryStore.shared.capture()
        }
    }
    private var recordTile: some View {
        ActionTile(icon: "record.circle", color: .red, title: L("Gravar tela"), subtitle: L("vídeo ou GIF"),
                   help: L("Escolha uma área (ou ↩ para a tela toda) e grave. O arquivo vai para a Mesa.")) {
            ScreenRecorder.shared.start(gif: false)
        }
        .contextMenu { Button(L("Gravar GIF")) { ScreenRecorder.shared.start(gif: true) } }
    }
    private var scrollTile: some View {
        ActionTile(icon: "arrow.down.doc", color: .blue, title: L("Captura com rolagem"), subtitle: L("página inteira"),
                   help: L("Escolha a área que rola: o Menew rola sozinho e junta tudo numa imagem comprida.")) {
            ScrollCapture.start()
        }
    }
    private var ocrTile: some View {
        ActionTile(icon: "text.viewfinder", color: .green, title: L("Texto da tela"), subtitle: L("copia o texto"),
                   help: L("Selecione uma área da tela e o texto dela vai para o clipboard.")) {
            TextRecognizer.captureScreenText()
        }
    }
    private var qrTile: some View {
        ActionTile(icon: "qrcode.viewfinder", color: .indigo, title: L("Ler QR code"), subtitle: L("da tela"),
                   help: L("Selecione o QR code na tela e o conteúdo vai para o clipboard.")) {
            QRCode.scanScreen()
        }
    }
    private var colorTile: some View {
        ActionTile(icon: "eyedropper.halffull", color: Theme.violet, title: L("Conta-gotas"), subtitle: L("copia o hex"),
                   help: L("Clique em qualquer ponto da tela para copiar a cor em hexadecimal.")) {
            tb.pickColor(clipboard: clipboard)
        }
    }
    private var screenAskTile: some View {
        ActionTile(icon: "text.bubble", color: .pink, title: L("Perguntar à tela"), subtitle: L("explica, traduz"),
                   help: L("Selecione uma área da tela e pergunte à IA do Mac: explicar, resumir, traduzir.")) {
            ScreenAsk.shared.start()
        }
    }
    private var askTile: some View {
        ActionTile(icon: "bubble.left.and.text.bubble.right", color: Theme.violet, title: L("Perguntar à IA"), subtitle: L("no Mac"),
                   help: L("Abre a paleta pronta para perguntar à IA do Mac.")) {
            (NSApp.delegate as? AppDelegate)?.palette.show(query: L("ia") + " ")
        }
    }
    private var agentTile: some View {
        ActionTile(icon: "wand.and.sparkles", color: .indigo, title: L("Fazer por mim"), subtitle: L("em linguagem natural"),
                   help: L("Diga o que quer, como “modo escuro e abre o Safari”, e o Menew monta os passos.")) {
            (NSApp.delegate as? AppDelegate)?.palette.show(query: L("faz") + " ")
        }
    }
    private var aiSettingsTile: some View {
        ActionTile(icon: "slider.horizontal.3", color: .gray, title: L("Recursos de IA"), subtitle: L("ligar e desligar"),
                   help: L("Veja todos os recursos de IA, como usar cada um e desligue os que não quiser.")) {
            SettingsWindow.shared.show(.ai)
        }
    }
    private var recordAudioTile: some View {
        ActionTile(icon: "waveform", color: .red, title: RecordingStore.shared.isRecording ? L("Parar a gravação") : L("Gravar áudio"),
                   subtitle: L("vira ata"), help: L("Grava o microfone (e o som do Mac numa chamada). O Mac transcreve e a IA escreve a ata com tarefas."),
                   on: RecordingStore.shared.isRecording) {
            RecordingStore.shared.toggle()
        }
        .contextMenu { Button(L("Gravações")) { MenewWindow.shared.show(.recordings) } }
    }
    private var captionsTile: some View {
        ActionTile(icon: "captions.bubble.fill", color: .indigo, title: L("Legendas ao vivo"), subtitle: L("e tradução"),
                   help: L("Legendas do som do Mac (chamadas, vídeos) ou do microfone, traduzidas na hora. Tudo no Mac."),
                   on: LiveCaptions.shared.running) {
            LiveCaptions.shared.toggle()
        }
    }
    private var iphoneTile: some View {
        ActionTile(icon: "iphone.rear.camera", color: .green, title: L("Do iPhone"), subtitle: L("foto ou scan"),
                   help: L("Tire uma foto, escaneie um documento ou desenhe no iPhone ou iPad: o resultado vai para o clipboard. Clique com o botão direito para mandar à estante ou copiar só o texto.")) {
            ContinuityCamera.shared.showMenu(.clipboard)
        }
        .contextMenu {
            Button(L("Do iPhone para a estante")) { ContinuityCamera.shared.showMenu(.shelf) }
            Button(L("Do iPhone, só o texto")) { ContinuityCamera.shared.showMenu(.text) }
        }
    }
    private var organizeTile: some View {
        ActionTile(icon: "folder.badge.gearshape", color: .blue, title: L("Organizar arquivos"), subtitle: L("pelo conteúdo"),
                   help: L("Lê os arquivos de uma pasta (Downloads, por padrão) e sugere nomes claros e pastas. Você revisa antes; dá para desfazer.")) {
            OrganizerWindow.shared.show()
        }
    }
    private var shelfTile: some View {
        ActionTile(icon: "tray.full.fill", color: Theme.indigo, title: L("Estante"), subtitle: L("arraste e solte"),
                   help: L("Solte arquivos, links e textos e leve todos juntos para outro app. Com imagens e PDFs, converte, reduz e junta.")) {
            (NSApp.delegate as? AppDelegate)?.shelf.toggle()
        }
    }
    private var plainTile: some View {
        ActionTile(icon: "textformat", color: .brown, title: L("Limpar formatação"), subtitle: L("do texto copiado"),
                   help: L("Tira fonte, cor e links do texto copiado. Cole como texto simples.")) {
            tb.plainTextClipboard()
        }
    }
    private var ejectTile: some View {
        ActionTile(icon: "eject.fill", color: .mint, title: L("Ejetar discos"),
                   subtitle: tb.ejectableCount == 0 ? L("nenhum conectado") : L("%d conectado(s)", tb.ejectableCount),
                   help: L("Ejeta com segurança todos os discos externos e pendrives."),
                   disabled: tb.ejectableCount == 0) { tb.ejectAll() }
    }
    private var trashTile: some View {
        ActionTile(icon: "trash", color: .red, title: L("Esvaziar lixeira"), subtitle: L("pede confirmação"),
                   help: L("Apaga para sempre o que está na Lixeira. Pergunta antes.")) { tb.emptyTrash() }
    }
    private var lockTile: some View {
        ActionTile(icon: "lock.fill", color: .gray, title: L("Bloquear tela"), subtitle: L("pede a senha"),
                   help: L("Apaga a tela na hora. Para voltar, use Touch ID ou sua senha.")) { tb.lockScreen() }
    }
    private var blackScreenTile: some View {
        ActionTile(icon: "sparkles.tv", color: .cyan, title: L("Limpar tela"), subtitle: L("tela preta"),
                   help: L("Deixa todas as telas pretas para ver manchas. Dois cliques para sair.")) {
            cleaning.blackScreen()
        }
    }
    private var keyboardTile: some View {
        ActionTile(icon: "keyboard", color: .teal, title: L("Limpar teclado"),
                   subtitle: cleaning.keyboardLocked ? L("travado") : L("trava por 2 min"),
                   help: L("Bloqueia todas as teclas por 2 minutos para você limpar. Destrava com um clique."),
                   on: cleaning.keyboardLocked) {
            if !cleaning.lockKeyboard() { tb.show(L("Libere o Menew em Acessibilidade")) }
        }
    }
    private var freeSpaceTile: some View {
        ActionTile(icon: "sparkles", color: .blue, title: L("Liberar espaço"), subtitle: L("caches e lixo"),
                   help: L("Encontra caches, logs e arquivos grandes. Você revisa antes de apagar."), action: openCleaner)
    }
    private var uninstallTile: some View {
        ActionTile(icon: "trash.square", color: .red, title: L("Desinstalar app"), subtitle: L("com as sobras"),
                   help: L("Escolha um app: ele e as preferências, caches e dados que deixou vão para a Lixeira.")) {
            Uninstaller.show()
        }
    }
    private var loginTile: some View {
        ActionTile(icon: "power.circle", color: .orange, title: L("Itens de login"), subtitle: L("o que abre com o Mac"),
                   help: L("Veja os agentes e serviços que os apps instalaram para abrir com o Mac ou rodar escondidos.")) {
            StartupItems.show()
        }
    }
    private var scriptsTile: some View {
        ActionTile(icon: "terminal", color: .gray, title: L("Scripts"), subtitle: L("viram comandos"),
                   help: L("Cada script desta pasta vira um comando da paleta, como no Raycast.")) {
            ScriptCommands.openFolder()
        }
    }
    private var activityTile: some View {
        ActionTile(icon: "chart.bar.xaxis", color: .green, title: L("Monitor de Atividade"), subtitle: L("do macOS"),
                   help: L("Abre o Monitor de Atividade do macOS.")) {
            tb.open("/System/Applications/Utilities/Activity Monitor.app")
        }
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

    private var openSet: Set<String> { Set(openRaw.split(separator: "|").map(String.init)) }

    /// Seção que abre e fecha; fechada, mostra só o título e um resumo do que tem dentro
    @ViewBuilder
    private func section<C: View>(_ title: String, collapsible: Bool = true, @ViewBuilder _ content: () -> C) -> some View {
        let open = !collapsible || openSet.contains(title)
        if collapsible {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    var set = openSet
                    if open { set.remove(title) } else { set.insert(title) }
                    withAnimation(.snappy) { openRaw = set.sorted().joined(separator: "|") }
                } label: {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.primary)
                        if !open, let s = summary(title) {
                            Text(s).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glass()
                .accessibilityValue(open ? L("Aberta") : L("Fechada"))
                if open { content() }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                content()
            }
        }
    }

    private func summary(_ title: String) -> String? {
        switch title {
        case L("Foco"): FocusTimer.shared.segment != nil ? L("Em andamento") : L("25 min, com pausa no fim")
        case L("Controles"): L("Microfone, som, modo escuro e mais")
        case L("Som"): AudioRouter.shared.currentOutput?.name
        case L("Janelas"): L("Metades, cantos e terços")
        case L("Apps"): L("%d abertos", AppControl.running.count)
        case L("Perfis"): profiles.profiles.isEmpty ? L("Nenhum ainda") : profiles.profiles.map(\.name).joined(separator: ", ")
        case L("Automações"): automations.rules.isEmpty ? L("Nenhuma ainda") : L("%d ativas", automations.rules.filter(\.enabled).count)
        case L("Limpeza"): L("Espaço, desinstalar apps, itens de login")
        case L("Atalhos"): L("Captura, gravação, perguntar à tela, scripts")
        default: nil
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
