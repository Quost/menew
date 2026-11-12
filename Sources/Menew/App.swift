import AppKit
import Carbon
import SwiftUI

@main
@MainActor
enum MenewMain {
    static let delegate = AppDelegate()
    static func main() {
        // Rodados pelos agentes de IA: respondem e saem, sem abrir o app (nem a barra de menus)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: AgentHookCommand.flag) { AgentHookCommand.run(agent: args.count > i + 1 ? args[i + 1] : "") }
        if args.contains(MCPServer.flag) { MCPServer.run() }
        DemoMode.prepare()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if !DemoMode.isOn { Migration.run() }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
            Snapshot.run(into: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        } else if let i = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > i + 1 {
            Snapshot.preview(tab: CommandLine.arguments[i + 1])
        } else if CommandLine.arguments.contains("--hardware") {
            DisplayController.printReport()
        } else {
            app.delegate = delegate
        }
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let monitor = SystemMonitor()
    // `--demo`: histórico, notas e o resto com dados fictícios (ver DemoMode)
    let clipboard = DemoMode.isOn ? ClipboardManager.demo() : ClipboardManager()
    let toolbox = Toolbox()
    let internet = InternetInfo()
    let cleaner = Cleaner()
    let updater = UpdaterModel(enabled: !DemoMode.isOn)
    lazy var notes = DemoMode.isOn ? NotesStore.demo() : NotesStore(dir: clipboard.dir)  // migra notas.md na primeira vez
    let nav = PopoverState()
    let popoverClipState = ClipListState()
    lazy var clipPanel = ClipboardPanelController(manager: clipboard)
    lazy var welcome = WelcomeController(monitor: monitor)
    let shelf = ShelfController()
    lazy var palette: PaletteController = {
        let model = PaletteModel(toolbox: toolbox, clipboard: clipboard, notes: notes)
        model.isDemo = DemoMode.isOn
        model.openTab = { [weak self] tab in
            guard let self else { return }
            nav.tab = tab
            showPopover()
        }
        model.openNote = { [weak self] id in self?.openNote(id) }
        model.openClipboard = { [weak self] in self?.clipPanel.show() }
        model.checkForUpdates = { [weak self] in self?.updater.checkForUpdates() }
        model.openShelf = { [weak self] in self?.shelf.show(nearMouse: false) }
        return PaletteController(model: model)
    }()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    var isMenuOpen: Bool { popover.isShown }
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Uma cópia só: se o Menew já está aberto (por exemplo, a atualização reabriu junto com o login), esta sai.
        // Se duas abrirem no mesmo instante, fica a de número de processo menor, para nunca saírem as duas.
        // Execuções com opções de linha de comando (capturas de tela, testes) não contam.
        let me = ProcessInfo.processInfo.processIdentifier
        if !CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }),
           let id = Bundle.main.bundleIdentifier,
           // Só outra cópia do mesmo app (o mesmo .app aberto duas vezes); um Menew em outra pasta não fecha este
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0.processIdentifier < me && !$0.isTerminated && $0.bundleURL?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
           }) {
            NSApp.terminate(nil)
            return
        }
        UserDefaults.standard.register(defaults: [
            MenuBarItem.key: MenuBarItem.migratedDefault,
            "autoPaste": true,
            "maxItems": 300,
            "ignoreConcealed": true,
        ])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Menew")
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        // Tamanho fixo desde o início: com o SDK do macOS 26 o popover era posicionado com o tamanho
        // padrão (320 pt) e depois crescia para cima, por cima da barra de menus
        popover.contentSize = NSSize(width: 400, height: 600)
        let hosting = NSHostingController(rootView: PopoverRoot(nav: nav) { [unowned self] in
            MainView(
                nav: nav, monitor: monitor, clipboard: clipboard, toolbox: toolbox, internet: internet, notes: notes,
                cleaner: cleaner, updater: updater, clipState: popoverClipState,
                onPickClip: { [weak self] item, plain in self?.pickFromPopover(item, plain: plain) }
            )
        })
        hosting.sizingOptions = []
        popover.contentViewController = hosting

        monitor.onTick = { [weak self] in
            guard let self else { return }
            updateStatusItem()
            if !DemoMode.isOn { AutomationStore.shared.tick(monitor) }
        }
        updater.onPendingChange = { [weak self] in self?.updateStatusItem() }
        monitor.start()
        if DemoMode.isOn {
            // Nada é lido do Mac: nem clipboard, nem agenda, nem agentes; também não grava widgets nem o Spotlight
            DemoMode.populate(monitor: monitor, toolbox: toolbox, internet: internet)
        } else {
            clipboard.start()
            ProfileStore.shared.load(dir: clipboard.dir)
            AutomationStore.shared.load(dir: clipboard.dir)
            SystemHistory.shared.load(dir: clipboard.dir)
            BatteryLog.shared.load(dir: clipboard.dir)
            BatteryWear.shared.load(dir: clipboard.dir)
            MemoryStore.shared.load(base: clipboard.dir)
            MemoryFeed.start()
            RecordingStore.shared.load(base: clipboard.dir)
            ScreenTime.shared.load(dir: clipboard.dir)
        }
        shelf.startShakeDetection()
        NotchCenter.shared.refresh()
        if !DemoMode.isOn {
            AgentHub.shared.start()
            AgentUsageStore.shared.start()
            MCPBridge.start()
            MCPHTTP.shared.sync()
            WidgetBridge.shared.start(monitor: monitor)
            SpotlightNotes.shared.start(notes)
            AutomationStore.shared.start(toolbox: toolbox)
            TextExpander.shared.start(clipboard: clipboard)
            MeetingStore.shared.refreshEnabled()
        }
        FocusTimer.shared.attach(toolbox)
        PasteQueue.shared.attach(clipboard)
        PasteQueue.shared.onChange = { [weak self] in self?.updateStatusItem() }
        TimerStore.shared.onChange = { [weak self] in self?.updateStatusItem() }
        PresentationMode.shared.attach(toolbox)
        MenuBarPro.shared.attach(monitor)
        MenuBarPro.shared.openMenew = { [weak self] in self?.showPopover() }
        PresentationMode.shared.onChange = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()

        applyAppearance()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusItem()
                self?.applyAppearance()
                self?.shelf.startShakeDetection()
                TextExpander.shared.refresh()
            }
        }

        HotKeyCenter.shared.onClipboard = { [weak self] in
            if Module.clipboard.isOn { self?.clipPanel.toggle() }
        }
        HotKeyCenter.shared.onMenu = { [weak self] in self?.togglePopover() }
        HotKeyCenter.shared.onOCR = { if Module.actions.isOn { TextRecognizer.captureScreenText() } }
        HotKeyCenter.shared.onCapture = { if Module.actions.isOn { ScreenCapture.area() } }
        HotKeyCenter.shared.onRewrite = { Rewriter.shared.start() }
        HotKeyCenter.shared.onMemory = { MemoryStore.shared.capture() }
        HotKeyCenter.shared.onRecording = { RecordingStore.shared.toggle() }
        HotKeyCenter.shared.onPalette = { [weak self] in
            guard let self else { return }
            if popover.isShown { popover.performClose(nil) }
            if clipPanel.isVisible { clipPanel.close() }
            palette.toggle()
        }
        HotKeyCenter.shared.onMic = { [weak self] in
            guard Module.actions.isOn, let self else { return }
            MuteHUD.show(muted: toolbox.toggleMic())
        }
        HotKeyCenter.shared.register()
        RunawayWatch.shared.refresh()
        DragSnap.shared.refresh()
        // Bateria dos acessórios: lida a cada 10 min para avisar quando estiver acabando
        if !DemoMode.isOn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { AccessoryMonitor.shared.start() }
            // Perfis aparecem nas frases da Siri ("Ativar Trabalho no Menew")
            MenewShortcuts.updateAppShortcutParameters()
        }

        welcome.onOpenMenu = { [weak self] in self?.showPopover() }
        NotificationCenter.default.addObserver(forName: .closeMenu, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.popover.isShown == true { self?.popover.performClose(nil) } }
        }
        NotificationCenter.default.addObserver(forName: .showWelcome, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.popover.performClose(nil)
                self?.welcome.show()
            }
        }
        // Quem já usava o app (tem histórico ou notas) não vê a apresentação
        let dir = clipboard.dir
        let existing = ["history.json", "notes.json", "notas.md"].contains {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        if !DemoMode.isOn { welcome.showIfNeeded(existingUser: existing) }

        installEditMenu()
        // Notas protegidas pedem Touch ID de novo depois que o Mac trava ou dorme
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.notes.lockAll() }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.notes.lockAll() }
        }
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool { !notes.authenticating }

    /// Fechar o menu tranca de novo as notas protegidas
    func popoverDidClose(_ notification: Notification) {
        notes.lockAll()
        nav.isOpen = false
        monitor.isVisible = false
    }

    /// Sem menu principal o macOS não entrega ⌘V, ⌘C, ⌘X, ⌘A e ⌘Z aos campos de texto.
    /// Num app da barra de menus esse menu nunca aparece, só serve para os atalhos.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Undo", Selector(("undo:")), "z", .command),
            ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", .command),
            ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command),
            ("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            ("Select All", #selector(NSText.selectAll(_:)), "a", .command),
        ]
        for (title, action, key, mods) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            edit.addItem(item)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "Menew", action: nil, keyEquivalent: ""))
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Automático segue o sistema; Claro/Escuro forçam o tema em todas as janelas do app
    private func applyAppearance() {
        let choice = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        if NSApp.appearance?.name != choice.nsAppearance?.name { NSApp.appearance = choice.nsAppearance }
    }

    // MARK: Barra de menus

    private var lastStatusKey = ""

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        // Com ícones separados, as métricas ficam nos ícones próprios; aqui sobra o ícone do Menew
        if MenuBarItem.selected.contains(.temp) { Sensors.shared.refresh() }
        var segments = MenuBarPro.shared.isOn ? [] : MenuBarItem.selected.compactMap { $0.segment(monitor) }
        MenuBarPro.shared.update()
        if let focus = FocusTimer.shared.segment { segments.insert(focus, at: 0) }
        if let timer = TimerStore.shared.segment { segments.insert(timer, at: 0) }
        if let queue = PasteQueue.shared.segment { segments.insert(queue, at: 0) }
        // Apresentando: só o ícone, sem números de CPU, memória ou rede na tela compartilhada
        if PresentationMode.shared.isOn { segments = [] }
        let pending = updater.pendingVersion != nil
        let key = segments.map(\.key).joined(separator: "|") + (pending ? "|update" : "")
        guard key != lastStatusKey || button.image == nil else { return }
        lastStatusKey = key
        let image = StatusRenderer.image(segments: segments)
        button.image = pending ? Self.withUpdateDot(image) : image
        button.imagePosition = .imageOnly
    }

    /// Pontinho no canto do ícone: tem atualização esperando, sem abrir janela nenhuma
    private static func withUpdateDot(_ image: NSImage) -> NSImage {
        // Espaço extra à direita para o ponto não encostar no texto
        let d: CGFloat = 5, gap: CGFloat = 2
        let size = NSSize(width: image.size.width + gap + d, height: image.size.height)
        let out = NSImage(size: size, flipped: false) { rect in
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - d, y: rect.maxY - d - 3, width: d, height: d)).fill()
            return true
        }
        // Continua modelo (template): o macOS pinta ícone e ponto na cor certa da barra
        out.isTemplate = image.isTemplate
        return out
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ key: String, _ icon: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            item.target = self
            menu.addItem(item)
        }
        add(L("Paleta de comandos"), "", "command", #selector(openPalette))
        if Module.clipboard.isOn { add(L("Histórico do clipboard"), "", "doc.on.clipboard", #selector(openClipPanel)) }
        if Module.actions.isOn {
            add(L("Capturar tela"), "", "camera.viewfinder", #selector(captureScreen))
            add(L("Copiar texto da tela"), "", "text.viewfinder", #selector(captureText))
            add(L("Ler QR code da tela"), "", "qrcode.viewfinder", #selector(scanQR))
            add(L("Estante"), "", "tray.full", #selector(openShelf))
        }
        add(L("Limpar teclado"), "", "keyboard", #selector(lockKeyboard))
        add(L("Limpar tela"), "", "sparkles.tv", #selector(blackScreen))
        menu.addItem(.separator())
        add(L("Reportar um problema…"), "", "ladybug", #selector(reportBug))
        add(L("Sugerir uma ideia…"), "", "lightbulb", #selector(suggestIdea))
        add(L("Pagar um café ao autor…"), "", "cup.and.saucer", #selector(buyCoffee))
        menu.addItem(.separator())
        if let v = updater.pendingVersion {
            add(L("Atualizar para a versão %@…", v), "", "arrow.down.circle.fill", #selector(showPendingUpdate))
        } else {
            add(L("Procurar atualizações…"), "", "arrow.down.circle", #selector(checkForUpdates))
        }
        add(L("Ajustes…"), ",", "gearshape", #selector(openSettings))
        add(L("Sair do Menew"), "q", "power", #selector(quit))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openClipPanel() { clipPanel.show() }
    @objc private func openPalette() { palette.show() }
    @objc private func openShelf() { shelf.toggle() }
    @objc private func captureText() { TextRecognizer.captureScreenText() }
    @objc private func scanQR() { QRCode.scanScreen() }
    @objc private func captureScreen() { ScreenCapture.area() }
    @objc private func lockKeyboard() { toolbox.cleaning.lockKeyboard() }
    @objc private func blackScreen() { toolbox.cleaning.blackScreen() }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func showPendingUpdate() { updater.showPendingUpdate() }
    @objc private func reportBug() { popover.performClose(nil); Feedback.reportBug() }
    @objc private func suggestIdea() { popover.performClose(nil); Feedback.suggestIdea() }
    @objc private func buyCoffee() { popover.performClose(nil); Feedback.buyCoffee() }
    @objc private func openSettings() { SettingsWindow.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// "Liberar espaço" pela janela Menew: abre a limpeza no menu
    func openCleanerFromHub() {
        nav.tab = .cleaner
        showPopover()
    }

    /// Abre uma nota na aba Notas (Spotlight, Atalhos)
    func openNote(_ id: UUID) {
        nav.tab = .notes
        nav.noteToOpen = id
        showPopover()
    }

    /// Resultado do Spotlight: abre a nota escolhida
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        if let id = SpotlightMemory.memoryID(from: userActivity) {
            MemoryStore.shared.query = ""
            MemoryStore.shared.selectedID = id
            MenewWindow.shared.show(.memory)
            return true
        }
        guard let id = SpotlightNotes.noteID(from: userActivity) else { return false }
        openNote(id)
        return true
    }

    /// Toque num widget (menew://system, menew://meetings…): abre o Menew na aba Sistema
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "menew" }) else { return }
        nav.tab = .system
        showPopover()
    }

    private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        // Atualização achada em segundo plano: a janela do Sparkle abre quando a pessoa clica no ícone
        if updater.pendingVersion != nil { updater.showPendingUpdate(); return }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        popoverClipState.query = ""
        popoverClipState.focusToken += 1
        NSApp.activate(ignoringOtherApps: true)
        nav.isOpen = true
        monitor.isVisible = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func pickFromPopover(_ item: ClipItem, plain: Bool) {
        popover.performClose(nil)
        previousApp?.activate()
        clipboard.paste(item, plainText: plain)
    }
}

// MARK: Desenho do item da barra

enum StatusSegment {
    case stat(String, String)   // rótulo pequeno em cima, valor embaixo
    case net(String, String)    // ↓ e ↑ empilhados
    case graph([Double])        // mini gráfico de barras (0…1)

    var key: String {
        switch self {
        case .stat(let a, let b): "\(a)\(b)"
        case .net(let a, let b): "\(a)\(b)"
        case .graph(let v): v.map { String(Int($0 * 16)) }.joined(separator: ",")
        }
    }
}

enum StatusRenderer {
    static func image(segments: [StatusSegment], showIcon: Bool = true) -> NSImage {
        let height: CGFloat = 22
        let iconSize: CGFloat = 15
        let gap: CGFloat = 7
        let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        let netFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attrs: (NSFont) -> [NSAttributedString.Key: Any] = { [.font: $0, .foregroundColor: NSColor.black] }

        // Largura de cada segmento, com largura mínima para o texto não "pular"
        let widths: [CGFloat] = segments.map { seg in
            switch seg {
            case .stat(let l, let v):
                let minV = ("100%" as NSString).size(withAttributes: attrs(valueFont)).width
                return max((l as NSString).size(withAttributes: attrs(labelFont)).width,
                           (v as NSString).size(withAttributes: attrs(valueFont)).width, minV)
            case .net(let d, let u):
                let minW = ("↓ 99.9M" as NSString).size(withAttributes: attrs(netFont)).width
                return max(("↓ " + d as NSString).size(withAttributes: attrs(netFont)).width,
                           ("↑ " + u as NSString).size(withAttributes: attrs(netFont)).width, minW)
            case .graph(let v):
                return CGFloat(v.count) * 2.5
            }
        }
        let lead = showIcon ? iconSize + gap : 2
        let total = segments.isEmpty ? iconSize : lead + widths.reduce(0) { $0 + $1 + gap } - gap + (showIcon ? 4 : 2)
        let img = NSImage(size: NSSize(width: ceil(total), height: height), flipped: false) { _ in
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            if showIcon || segments.isEmpty, let sym = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let s = sym.size
                sym.draw(in: NSRect(x: (iconSize - s.width) / 2, y: (height - s.height) / 2, width: s.width, height: s.height))
            }
            var x = lead
            for (seg, w) in zip(segments, widths) {
                switch seg {
                case .stat(let l, let v):
                    let ls = (l as NSString).size(withAttributes: attrs(labelFont))
                    let vs = (v as NSString).size(withAttributes: attrs(valueFont))
                    (l as NSString).draw(at: NSPoint(x: x + (w - ls.width) / 2, y: 11.5), withAttributes: attrs(labelFont))
                    (v as NSString).draw(at: NSPoint(x: x + (w - vs.width) / 2, y: -0.5), withAttributes: attrs(valueFont))
                case .net(let d, let u):
                    ("↑ " + u as NSString).draw(at: NSPoint(x: x, y: 10.5), withAttributes: attrs(netFont))
                    ("↓ " + d as NSString).draw(at: NSPoint(x: x, y: 0), withAttributes: attrs(netFont))
                case .graph(let v):
                    NSColor.black.withAlphaComponent(0.25).setFill()
                    NSRect(x: x, y: 3, width: w, height: 0.8).fill()
                    NSColor.black.setFill()
                    for (i, f) in v.enumerated() {
                        let h = max(1, 16 * CGFloat(min(max(f, 0), 1)))
                        NSBezierPath(roundedRect: NSRect(x: x + CGFloat(i) * 2.5, y: 3, width: 1.8, height: h),
                                     xRadius: 0.6, yRadius: 0.6).fill()
                    }
                }
                x += w + gap
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
