import MenewShared
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
        AccessoryMonitor.shared.showDemo()
        SystemHistory.shared.showDemo()
        ScreenTime.shared.showDemo()
        Sensors.shared.showDemo()
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
            monitor.batteryHealth = BatteryHealth(cycles: 112, healthPercent: 96, temperature: nil, adapterWatts: 70, systemWatts: 8.4)
            BatteryLog.shared.set(BatteryLog.demo)
            monitor.coreLoads = [0.12, 0.08, 0.15, 0.05, 0.09, 0.11, 0.42, 0.31, 0.18, 0.25]
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
                // Janela Menew: algumas seções
                MemoryStore.shared.showDemo()
                for sec in [HubSection.overview, .memory, .tools, .performance] {
                    let hs = HubState()
                    hs.section = sec
                    render(HubView(state: hs, monitor: monitor, clipboard: clipboard, notes: notes, internet: internet, toolbox: toolbox, updater: UpdaterModel(enabled: false)),
                           size: NSSize(width: 1040, height: 680), dark: dark, to: dir.appendingPathComponent("hub-\(sec.rawValue)-\(suffix).png"))
                }
                let ss = HubState()
                ss.section = .settings
                ss.category = .general
                render(HubView(state: ss, monitor: monitor, clipboard: clipboard, notes: notes, internet: internet, toolbox: toolbox, updater: UpdaterModel(enabled: false)),
                       size: NSSize(width: 1040, height: 680), dark: dark, to: dir.appendingPathComponent("hub-settings-\(suffix).png"))
                RecordingStore.shared.showDemo()
                let rs = HubState()
                rs.section = .recordings
                render(HubView(state: rs, monitor: monitor, clipboard: clipboard, notes: notes, internet: internet, toolbox: toolbox, updater: UpdaterModel(enabled: false)),
                       size: NSSize(width: 1040, height: 680), dark: dark, to: dir.appendingPathComponent("hub-recordings-\(suffix).png"))
                // Grafo do conhecimento com os dados de exemplo
                let kg = KnowledgeGraph.build(memory: MemoryStore.shared.items, notes: [])
                let gsize = CGSize(width: 760, height: 460)
                render(KnowledgeGraphView(graph: kg, positions: kg.layout(in: gsize), onTopic: { _ in }, onMemory: { _ in }, onNote: { _ in })
                        .frame(width: gsize.width, height: gsize.height).padding(20).background(Theme.windowFill),
                       size: NSSize(width: 800, height: 500), dark: dark, to: dir.appendingPathComponent("graph-\(suffix).png"))
                // Uma página de grupo da aba Ações
                render(ActionsView(tb: toolbox, clipboard: clipboard, group: .windows) {}.frame(width: 400, height: 600).background(Theme.popoverFill),
                       size: NSSize(width: 400, height: 600), dark: dark, to: dir.appendingPathComponent("actions-group-\(suffix).png"))
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
                render(ScreenTimeCard().padding(14).frame(width: 400, alignment: .top).background(Theme.windowFill),
                       size: NSSize(width: 400, height: 640), dark: dark, to: dir.appendingPathComponent("screentime-\(suffix).png"))
                render(SystemHistoryCard().padding(14).frame(width: 400, alignment: .top).background(Theme.windowFill),
                       size: NSSize(width: 400, height: 370), dark: dark, to: dir.appendingPathComponent("history-\(suffix).png"))
                render(SettingsWindowView(clipboard: clipboard, monitor: monitor, updater: UpdaterModel(enabled: false), initial: .clipboard),
                       size: NSSize(width: 760, height: 560), dark: dark, to: dir.appendingPathComponent("settings-window-\(suffix).png"))
                render(SettingsWindowView(clipboard: clipboard, monitor: monitor, updater: UpdaterModel(enabled: false), initial: .ai),
                       size: NSSize(width: 760, height: 760), dark: dark, to: dir.appendingPathComponent("settings-ai-\(suffix).png"))
                render(SettingsWindowView(clipboard: clipboard, monitor: monitor, updater: UpdaterModel(enabled: false), initial: .notch),
                       size: NSSize(width: 760, height: 820), dark: dark, to: dir.appendingPathComponent("settings-notch-\(suffix).png"))
                render(VStack(spacing: 10) { SensorsCard(); CoreBars(loads: [0.12, 0.08, 0.15, 0.05, 0.09, 0.11, 0.42, 0.31, 0.18, 0.25]).card() }
                        .padding(14).frame(width: 400, alignment: .top).background(Theme.windowFill),
                       size: NSSize(width: 400, height: 380), dark: dark, to: dir.appendingPathComponent("sensors-\(suffix).png"))
                render(MetricPanel(item: .cpu, m: monitor, openMenew: {}), size: NSSize(width: 340, height: 520), dark: dark,
                       to: dir.appendingPathComponent("metric-cpu-\(suffix).png"))
                render(MetricPanel(item: .ram, m: monitor, openMenew: {}), size: NSSize(width: 340, height: 420), dark: dark,
                       to: dir.appendingPathComponent("metric-ram-\(suffix).png"))
                render(MetricPanel(item: .battery, m: monitor, openMenew: {}), size: NSSize(width: 340, height: 560), dark: dark,
                       to: dir.appendingPathComponent("metric-battery-\(suffix).png"))
                render(MetricPanel(item: .net, m: monitor, openMenew: {}), size: NSSize(width: 340, height: 400), dark: dark,
                       to: dir.appendingPathComponent("metric-net-\(suffix).png"))
                render(UninstallerView(model: Uninstaller.demo()), size: NSSize(width: 520, height: 440), dark: dark,
                       to: dir.appendingPathComponent("uninstaller-\(suffix).png"))
                render(StartupItemsView(demo: StartupItems.demo), size: NSSize(width: 520, height: 460), dark: dark,
                       to: dir.appendingPathComponent("startup-\(suffix).png"))
                // Widgets: os quatro, pequeno e médio, como aparecem na mesa
                let ws = WidgetSnapshot.demo(lang: L10n.current.rawValue)
                func card(_ v: some View, _ w: CGFloat) -> some View {
                    v.padding(16).frame(width: w, height: 170)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                }
                render(VStack(spacing: 16) {
                    HStack(spacing: 16) { card(SystemWidgetView(ws, size: .small), 170); card(MeetingsWidgetView(ws, size: .medium), 356) }
                    HStack(spacing: 16) { card(TimersWidgetView(ws, size: .medium), 356); card(ScreenTimeWidgetView(ws, size: .small), 170) }
                    HStack(spacing: 16) { card(SystemWidgetView(ws, size: .medium), 356); card(MeetingsWidgetView(ws, size: .small), 170) }
                }
                .padding(24).background(LinearGradient(colors: [Color(red: 0.42, green: 0.45, blue: 0.62), Color(red: 0.62, green: 0.52, blue: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)),
                       size: NSSize(width: 590, height: 606), dark: dark, to: dir.appendingPathComponent("widgets-\(suffix).png"))
                render(IntentsShowcase().frame(width: 520), size: NSSize(width: 520, height: 470), dark: dark,
                       to: dir.appendingPathComponent("intents-\(suffix).png"))
                render(BatteryCard(battery: BatteryInfo(percent: 82, charging: false, onAC: false, minutesLeft: 312),
                                   health: BatteryHealth(cycles: 112, healthPercent: 96, temperature: 31, adapterWatts: nil, systemWatts: 8.4))
                        .padding(14).frame(width: 400, alignment: .top).background(Theme.windowFill),
                       size: NSSize(width: 400, height: 250), dark: dark, to: dir.appendingPathComponent("battery-\(suffix).png"))
                // Legendas ao vivo sobre um "vídeo" escuro
                let lc = LiveCaptions()
                lc.from = "en-US"
                lc.to = L10n.current == .en ? "pt" : LiveCaptions.defaultTarget
                lc.showDemo(original: "…so the release moves to Thursday, and we’ll review the numbers together next week.",
                            translated: L("…então o lançamento passa para quinta, e revisamos os números juntos na semana que vem."))
                render(ZStack(alignment: .bottom) {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.3), Color(red: 0.32, green: 0.24, blue: 0.36)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "person.2.fill").font(.system(size: 90)).foregroundStyle(.white.opacity(0.18)).frame(maxHeight: .infinity)
                    CaptionsView(model: lc).frame(width: 640, height: 132).padding(.bottom, 20)
                }
                .frame(width: 700, height: 360), size: NSSize(width: 700, height: 360), dark: dark,
                       to: dir.appendingPathComponent("captions-\(suffix).png"))
                // Notch, fase 2: o painel ao passar o mouse e a área de soltar arquivos
                let hm = NotchHoverModel()
                hm.shown = true
                hm.meeting = Meeting(id: "demo", title: L("Alinhamento semanal"), start: Date().addingTimeInterval(14 * 60), end: Date().addingTimeInterval(44 * 60),
                                     link: URL(string: "https://meet.example.com/abc"), color: .orange)
                hm.focusEnd = Date().addingTimeInterval(18 * 60)
                let dm = NotchHoverModel()
                dm.shown = true
                dm.mode = .drop
                render(VStack(spacing: 18) {
                    NotchHoverView(model: hm, notch: CGSize(width: 200, height: 37)).frame(width: 460, height: 150)
                    NotchHoverView(model: dm, notch: CGSize(width: 200, height: 37)).frame(width: 360, height: 110)
                }
                .padding(.bottom, 18).frame(width: 560)
                .background(LinearGradient(colors: [Color(red: 0.42, green: 0.45, blue: 0.62), Color(red: 0.62, green: 0.52, blue: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)),
                       size: NSSize(width: 560, height: 296), dark: dark, to: dir.appendingPathComponent("notch-hover-\(suffix).png"))
                // Notch: três momentos, sobre um fundo de barra de menus
                for (name, act) in [("meeting", NotchCenter.Activity.meeting(title: L("Alinhamento semanal"), start: Date().addingTimeInterval(95), hasLink: true)),
                                    ("timer", .timer(label: L("Chá"), end: Date().addingTimeInterval(9 * 60 + 41))),
                                    ("copied", .flash(icon: "doc.on.doc.fill", color: .green, text: L("Copiado")))] {
                    let c = NotchCenter()
                    c.showDemo(act)
                    render(NotchView(center: c, notch: CGSize(width: 200, height: 37)).frame(width: 440, height: 75),
                           size: NSSize(width: 440, height: 75), dark: dark,
                           background: NSColor(calibratedRed: 0.42, green: 0.45, blue: 0.62, alpha: 1),
                           to: dir.appendingPathComponent("notch-\(name)-\(suffix).png"))
                }
                let ask = ScreenAsk()
                ask.image = NSImage(size: NSSize(width: 320, height: 60), flipped: false) { r in
                    NSColor.white.setFill(); r.fill()
                    ("error: cannot find 'userName' in scope" as NSString).draw(at: NSPoint(x: 8, y: 22),
                        withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.systemRed])
                    return true
                }
                ask.screenText = "error: cannot find 'userName' in scope\nProfileView.swift:42:17\nBuild failed: 1 error, 3 warnings"
                ask.asked = L("Explicar")
                ask.answer = L("O projeto não compilou porque o código usa “userName”, mas nada com esse nome existe ali. Declare a variável ou corrija o nome na linha 42 de ProfileView.swift.")
                render(ScreenAskView(model: ask), size: NSSize(width: 500, height: 440), dark: dark,
                       to: dir.appendingPathComponent("screen-ask-\(suffix).png"))
                let rw = Rewriter()
                rw.original = L("oi pessoal, a reuniao de amanha foi cancelada pq o cliente nao pode, vamo remarcar pra semana q vem")
                rw.chosen = .formal
                rw.result = L("Olá a todos, a reunião de amanhã foi cancelada porque o cliente não poderá comparecer. Vamos remarcá-la para a próxima semana.")
                render(RewriterView(model: rw), size: NSSize(width: 420, height: 330), dark: dark,
                       to: dir.appendingPathComponent("rewrite-\(suffix).png"))
                let qr = QRModel()
                qr.text = "https://menew.web.app"
                render(QRView(model: qr, close: {}), size: NSSize(width: 360, height: 480), dark: dark,
                       to: dir.appendingPathComponent("qr-\(suffix).png"))
                let answer = AIAnswer()
                answer.question = L("Como recuso uma reunião com educação?")
                answer.text = L("Agradeça o convite, explique em uma frase por que não vai conseguir participar e ofereça uma alternativa, como mandar suas ideias por escrito ou sugerir outro horário.")
                render(AIAnswerView(model: answer, close: {}), size: NSSize(width: 460, height: 300), dark: dark,
                       to: dir.appendingPathComponent("ai-answer-\(suffix).png"))
                if let m = MeetingStore.shared.next {
                    render(MeetingBanner(meeting: m, today: MeetingStore.shared.today, expanded: true, onJoin: {})
                            .padding(.top, 14).frame(width: 400, height: 260, alignment: .top).background(Theme.windowFill),
                           size: NSSize(width: 400, height: 260), dark: dark, to: dir.appendingPathComponent("agenda-\(suffix).png"))
                }
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

/// Para o site: a Siri respondendo, as ações no app Atalhos e uma nota achada no Spotlight (dados de exemplo)
private struct IntentsShowcase: View {
    private let actions: [(String, String, Color)] = [
        ("gauge.with.dots.needle.67percent", L("Obter medida do sistema"), .blue),
        ("doc.on.clipboard", L("Obter histórico do clipboard"), .purple),
        ("apple.intelligence", L("Reescrever texto com IA"), .pink),
        ("translate", L("Traduzir texto"), .teal),
        ("text.viewfinder", L("Obter texto da imagem"), .orange),
        ("photo", L("Converter imagem"), .green),
        ("calendar", L("Obter próxima reunião"), .red),
        ("timer", L("Iniciar timer"), .indigo),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .trailing, spacing: 8) {
                Text(L("Como está meu Mac no Menew?"))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor))
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform.circle.fill").font(.system(size: 22)).foregroundStyle(.linearGradient(colors: [.pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(L("CPU em %@, memória em %@, %@ livres no disco", "18%", "64%", "182 GB") + L(" e bateria em %@", "82%") + ".")
                        .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: 8) {
                Label(L("No app Atalhos"), systemImage: "square.2.layers.3d.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(actions, id: \.1) { icon, title, color in
                        HStack(spacing: 8) {
                            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
                            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                        }
                        .padding(7).background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Spotlight", systemImage: "magnifyingglass").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        Text(L("ata da reunião")).font(.system(size: 15))
                        Spacer()
                    }
                    .padding(10)
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "note.text").font(.system(size: 14)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.yellow.gradient))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("Ata da reunião de produto")).font(.system(size: 13, weight: .medium))
                            Text(L("Nota do Menew")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10).background(Color.accentColor.opacity(0.15))
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
        .background(Theme.windowFill)
    }
}
