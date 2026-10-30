import AppKit
import Carbon
import SwiftUI

@main
@MainActor
enum MenewMain {
    static let delegate = AppDelegate()
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Migration.run()
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
    let clipboard = ClipboardManager()
    let toolbox = Toolbox()
    let internet = InternetInfo()
    let cleaner = Cleaner()
    let updater = UpdaterModel(enabled: true)
    lazy var notes = NotesStore(dir: clipboard.dir)  // migra notas.md na primeira vez
    let nav = PopoverState()
    let popoverClipState = ClipListState()
    lazy var clipPanel = ClipboardPanelController(manager: clipboard)
    lazy var welcome = WelcomeController(monitor: monitor)
    let shelf = ShelfController()
    lazy var palette: PaletteController = {
        let model = PaletteModel(toolbox: toolbox, clipboard: clipboard, notes: notes)
        model.openTab = { [weak self] tab in
            guard let self else { return }
            nav.tab = tab
            showPopover()
        }
        model.openNote = { [weak self] id in
            guard let self else { return }
            nav.tab = .notes
            nav.noteToOpen = id
            showPopover()
        }
        model.openClipboard = { [weak self] in self?.clipPanel.show() }
        model.checkForUpdates = { [weak self] in self?.updater.checkForUpdates() }
        model.openShelf = { [weak self] in self?.shelf.show(nearMouse: false) }
        return PaletteController(model: model)
    }()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            AutomationStore.shared.tick(monitor)
        }
        updater.onPendingChange = { [weak self] in self?.updateStatusItem() }
        monitor.start()
        clipboard.start()
        ProfileStore.shared.load(dir: clipboard.dir)
        shelf.startShakeDetection()
        AutomationStore.shared.load(dir: clipboard.dir)
        AutomationStore.shared.start(toolbox: toolbox)
        TextExpander.shared.start(clipboard: clipboard)
        MeetingStore.shared.refreshEnabled()
        FocusTimer.shared.attach(toolbox)
        PasteQueue.shared.attach(clipboard)
        PasteQueue.shared.onChange = { [weak self] in self?.updateStatusItem() }
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

        welcome.onOpenMenu = { [weak self] in self?.showPopover() }
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
        welcome.showIfNeeded(existingUser: existing)

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
        var segments = MenuBarItem.selected.compactMap { $0.segment(monitor) }
        if let focus = FocusTimer.shared.segment { segments.insert(focus, at: 0) }
        if let queue = PasteQueue.shared.segment { segments.insert(queue, at: 0) }
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
            add(L("Copiar texto da tela"), "", "text.viewfinder", #selector(captureText))
            add(L("Estante"), "", "tray.full", #selector(openShelf))
        }
        add(L("Limpar teclado"), "", "keyboard", #selector(lockKeyboard))
        add(L("Limpar tela"), "", "sparkles.tv", #selector(blackScreen))
        menu.addItem(.separator())
        add(L("Reportar um problema…"), "", "ladybug", #selector(reportBug))
        add(L("Sugerir uma ideia…"), "", "lightbulb", #selector(suggestIdea))
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
    @objc private func lockKeyboard() { toolbox.cleaning.lockKeyboard() }
    @objc private func blackScreen() { toolbox.cleaning.blackScreen() }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func showPendingUpdate() { updater.showPendingUpdate() }
    @objc private func reportBug() { popover.performClose(nil); Feedback.reportBug() }
    @objc private func suggestIdea() { popover.performClose(nil); Feedback.suggestIdea() }
    @objc private func openSettings() { nav.tab = .settings; showPopover() }
    @objc private func quit() { NSApp.terminate(nil) }

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
    static func image(segments: [StatusSegment]) -> NSImage {
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
        let total = segments.isEmpty ? iconSize : iconSize + widths.reduce(0) { $0 + $1 + gap } - gap + 4
        let img = NSImage(size: NSSize(width: ceil(total), height: height), flipped: false) { _ in
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            if let sym = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let s = sym.size
                sym.draw(in: NSRect(x: (iconSize - s.width) / 2, y: (height - s.height) / 2, width: s.width, height: s.height))
            }
            var x = iconSize + gap
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
