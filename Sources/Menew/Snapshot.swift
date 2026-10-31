import AppKit
import SwiftUI

/// `Menew --snapshot <pasta>`: renderiza as telas em PNG (claro e escuro) e sai.
/// Usa um histórico fictício, nunca o clipboard real.
@MainActor
enum Snapshot {
    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Theme.flatGlass = !CommandLine.arguments.contains("--live-glass")
        let monitor = SystemMonitor()
        let clipboard = ClipboardManager.demo()
        MeetingStore.shared.showDemo()
        NetUsage.shared.showDemo()
        let toolbox = Toolbox()
        toolbox.keepAwake = true
        toolbox.displays.isDemo = true
        toolbox.displays.screens = [
            ScreenInfo(id: 1, name: L("Tela do Mac"), builtin: true, kind: .apple, brightness: 0.72),
            ScreenInfo(id: 2, name: "DELL P2419H", builtin: false, kind: .ddc, brightness: 0.5),
        ]
        let internet = InternetInfo()
        internet.speed = .done(SpeedResult(down: 224, up: 146, latency: 21, rpm: 425))
        internet.publicIP = "189.0.113.42"
        internet.devices = [
            BTDevice(name: "AirPods Pro", kind: .airpods, levels: [(L("E"), 90), (L("D"), 88), (L("Estojo"), 54)]),
            BTDevice(name: "Magic Mouse", kind: .mouse, levels: [("", 17)]),
        ]
        let notes = NotesStore.demo()
        WorldClock.shared.demo()
        ProfileStore.shared.demo()
        AutomationStore.shared.demo()
        monitor.start()
        // Só lê o disco: nada é apagado em modo captura
        let scanned = Cleaner()
        if CommandLine.arguments.contains("--scan") { scanned.scan(deep: false) }

        // Espera alguns ciclos para CPU/rede terem dados
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            // Dados fictícios onde a máquina real apareceria (rede, processos)
            monitor.isDemo = true
            monitor.localIP = "192.168.0.12"
            monitor.battery = BatteryInfo(percent: 80, charging: false, onAC: true, minutesLeft: nil)
            monitor.batteryHealth = BatteryHealth(cycles: 112, healthPercent: 96, temperature: nil, adapterWatts: 70)
            monitor.memPressure = .normal
            monitor.memTotal = 16 << 30
            monitor.memBreakdown = MemoryBreakdown(app: 6_400 << 20, wired: 2_100 << 20, compressed: 1_300 << 20)
            monitor.memUsed = monitor.memBreakdown.app + monitor.memBreakdown.wired + monitor.memBreakdown.compressed
            monitor.swapUsed = 0
            monitor.topProcesses = [
                ProcInfo(name: "Safari", cpu: 18.4, memKB: 1_450_000),
                ProcInfo(name: "WindowServer", cpu: 9.2, memKB: 420_000),
                ProcInfo(name: "Xcode", cpu: 6.1, memKB: 2_100_000),
                ProcInfo(name: "Music", cpu: 2.3, memKB: 310_000),
                ProcInfo(name: "Finder", cpu: 0.8, memKB: 160_000),
            ]
            for dark in [false, true] {
                let suffix = dark ? "dark" : "light"
                for tab in Tab.allCases {
                    let nav = PopoverState()
                    nav.tab = tab
                    let v = MainView(nav: nav, monitor: monitor, clipboard: clipboard, toolbox: toolbox, internet: internet,
                                     notes: notes, cleaner: Cleaner(), updater: UpdaterModel(enabled: false), clipState: ClipListState(), onPickClip: { _, _ in })
                    render(v, size: NSSize(width: 400, height: 600), dark: dark,
                           to: dir.appendingPathComponent("popover-\(tab)-\(suffix).png"))
                }
                if CommandLine.arguments.contains("--full-settings") { // Ajustes inteiros, para revisar o layout
                    render(SettingsView(clipboard: clipboard, monitor: monitor, updater: UpdaterModel(enabled: false)).background(Theme.windowFill),
                           size: NSSize(width: 400, height: 1900), dark: dark, to: dir.appendingPathComponent("settings-full-\(suffix).png"))
                    render(ActionsView(tb: toolbox, clipboard: clipboard, openCleaner: {}).background(Theme.windowFill),
                           size: NSSize(width: 400, height: 1500), dark: dark, to: dir.appendingPathComponent("actions-full-\(suffix).png"))
                    if let r = AutomationStore.shared.rules.first {
                        render(AutomationEditor(store: AutomationStore.shared, rule: r, onClose: {}).background(Theme.windowFill),
                               size: NSSize(width: 400, height: 700), dark: dark, to: dir.appendingPathComponent("automation-editor-\(suffix).png"))
                    }
                    if let p = ProfileStore.shared.profiles.first {
                        render(ProfileEditor(store: ProfileStore.shared, tb: toolbox, profile: p, onClose: {}).background(Theme.windowFill),
                               size: NSSize(width: 400, height: 600), dark: dark, to: dir.appendingPathComponent("profile-editor-\(suffix).png"))
                    }
                }
                if CommandLine.arguments.contains("--scan") {
                    let nav = PopoverState()
                    nav.tab = .cleaner
                    render(MainView(nav: nav, monitor: monitor, clipboard: clipboard, toolbox: toolbox, internet: internet,
                                    notes: notes, cleaner: scanned, updater: UpdaterModel(enabled: false), clipState: ClipListState(), onPickClip: { _, _ in }),
                           size: NSSize(width: 400, height: 600), dark: dark,
                           to: dir.appendingPathComponent("cleaner-results-\(suffix).png"))
                }
                for step in 0..<5 {
                    render(WelcomeView(monitor: monitor, onFinish: { _ in }, step: step), size: NSSize(width: 480, height: 560), dark: dark,
                           to: dir.appendingPathComponent("welcome\(step)-\(suffix).png"))
                }
                let paletteModel = PaletteModel(toolbox: toolbox, clipboard: clipboard, notes: notes)
                paletteModel.isDemo = true
                paletteModel.update()
                render(PaletteController.chrome(PaletteView(model: paletteModel)), size: PaletteController.size, dark: dark,
                       background: NSColor(calibratedRed: 0.3, green: 0.4, blue: 0.6, alpha: 1),
                       to: dir.appendingPathComponent("palette-\(suffix).png"))
                ShelfStore.shared.demo()
                render(ShelfController.chrome(ShelfView(store: ShelfStore.shared, onClose: {})), size: ShelfController.size, dark: dark,
                       background: NSColor(calibratedRed: 0.3, green: 0.4, blue: 0.6, alpha: 1),
                       to: dir.appendingPathComponent("shelf-\(suffix).png"))
                render(NotesView(store: notes, openID: notes.notes.first?.id)
                        .padding(.top, 14).frame(width: 400, height: 600).background(Theme.windowFill),
                       size: NSSize(width: 400, height: 600), dark: dark,
                       to: dir.appendingPathComponent("note-editor-\(suffix).png"))
                render(NotesView(store: notes, openID: notes.notes.first(where: \.isPasswords)?.id)
                        .padding(.top, 14).frame(width: 400, height: 600).background(Theme.windowFill),
                       size: NSSize(width: 400, height: 600), dark: dark,
                       to: dir.appendingPathComponent("note-passwords-\(suffix).png"))
                // Editor de captura sobre uma captura do próprio Menew, com uma marca de cada tipo
                if let shot = NSImage(contentsOf: dir.appendingPathComponent("popover-system-\(suffix).png")),
                   let doc = CaptureDocument(image: shot) {
                    let w = doc.size.width, h = doc.size.height
                    doc.marks = [
                        CaptureMark(kind: .rect, a: CGPoint(x: w * 0.04, y: h * 0.27), b: CGPoint(x: w * 0.96, y: h * 0.5), color: .red),
                        CaptureMark(kind: .arrow, a: CGPoint(x: w * 0.75, y: h * 0.72), b: CGPoint(x: w * 0.55, y: h * 0.52), color: .red),
                        CaptureMark(kind: .text, a: CGPoint(x: w * 0.42, y: h * 0.73), b: .zero, color: .red, text: L("Seta")),
                        CaptureMark(kind: .pen, a: .zero, b: .zero, color: .yellow,
                                    points: (0...40).map { i in CGPoint(x: w * (0.1 + Double(i) * 0.008), y: h * (0.9 + sin(Double(i) / 4) * 0.015)) }),
                        CaptureMark(kind: .blur, a: CGPoint(x: w * 0.04, y: h * 0.05), b: CGPoint(x: w * 0.6, y: h * 0.12), color: .clear),
                    ]
                    render(CaptureEditor(doc: doc, close: {}), size: NSSize(width: 620, height: 820), dark: dark,
                           to: dir.appendingPathComponent("capture-\(suffix).png"))
                }
                let state = ClipListState()
                for (i, sel) in [0, 2, 3].enumerated() {
                    state.selection = sel
                    let panel = ClipboardPanelView(manager: clipboard, state: state, onActivate: { _, _ in })
                        .frame(width: 780, height: 500)
                    render(panel, size: NSSize(width: 780, height: 500), dark: dark,
                           to: dir.appendingPathComponent("panel\(i)-\(suffix).png"))
                }
                render(KeyboardLockView(controller: toolbox.cleaning), size: NSSize(width: 900, height: 560), dark: dark,
                       background: NSColor(calibratedRed: 0.3, green: 0.4, blue: 0.6, alpha: 1),
                       to: dir.appendingPathComponent("keyboard-lock-\(suffix).png"))
            }
            // Barra de menus: a combinação usada no site e algumas opções
            let bars: [(String, [MenuBarItem])] = [("all", [.cpu, .ram, .net]), ("graph", [.cpuGraph, .ram, .net]),
                                                   ("icon", []), ("battery", [.cpu, .ram, .disk, .battery])]
            for (name, items) in bars {
                let img = StatusRenderer.image(segments: items.map(\.sample))
                let v = Image(nsImage: img).padding(.horizontal, 8).frame(height: 24)
                render(v, size: NSSize(width: img.size.width + 16, height: 24), dark: false,
                       background: NSColor(white: 0.93, alpha: 1), scale: 4,
                       to: dir.appendingPathComponent("statusbar-\(name).png"))
            }
            NSApp.terminate(nil)
        }
    }

    /// `Menew --preview <aba>`: abre a tela numa janela de verdade (para ver o Liquid Glass) e imprime o número da janela
    static func preview(tab: String) {
        let nav = PopoverState()
        nav.tab = Tab.allCases.first { "\($0)" == tab } ?? .actions
        let toolbox = Toolbox()
        let v = MainView(nav: nav, monitor: { let m = SystemMonitor(); m.start(); return m }(), clipboard: ClipboardManager.demo(),
                         toolbox: toolbox, internet: InternetInfo(), notes: NotesStore.demo(), cleaner: Cleaner(),
                         updater: UpdaterModel(enabled: false), clipState: ClipListState(), onPickClip: { _, _ in })
        let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 600), styleMask: [.titled, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        let host = NSHostingView(rootView: v)
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        win.contentView = effect
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { print(win.windowNumber); fflush(stdout) }
    }

    static func render<V: View>(_ view: V, size: NSSize, dark: Bool, background: NSColor? = nil,
                                scale: CGFloat = 2, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let container = NSView(frame: host.frame)
        container.wantsLayer = true
        win.contentView = container
        container.appearance = win.appearance
        container.layer?.backgroundColor = (background ?? (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1))).cgColor
        container.addSubview(host)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        host.display()

        let px = NSSize(width: size.width * scale, height: size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px.width), pixelsHigh: Int(px.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        container.cacheDisplay(in: container.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
