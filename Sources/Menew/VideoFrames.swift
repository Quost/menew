import AppKit
import SwiftUI

/// `Menew --demo --video-frames <pasta>`: renderiza, com os dados fictícios, os quadros-chave do vídeo de
/// divulgação (abas do menu, busca no clipboard, palette sendo digitada, CPU e notch) e sai.
/// `scripts/make-video.swift` monta esses quadros no vídeo. Nada vem da tela real, então não precisa de
/// permissão de gravação e funciona em qualquer idioma (`-language`).
@MainActor
enum VideoFrames {
    static let flag = "--video-frames"

    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Theme.flatGlass = true
        let monitor = SystemMonitor()
        let clipboard = ClipboardManager.demo()
        MeetingStore.shared.showDemo()
        NetUsage.shared.showDemo()
        SystemHistory.shared.showDemo()
        Sensors.shared.showDemo()
        let toolbox = Toolbox()
        toolbox.keepAwake = true
        DemoMode.fakeDisplays(toolbox)
        let internet = InternetInfo()
        DemoMode.fakeInternet(internet)
        let notes = NotesStore.demo()
        WorldClock.shared.demo()
        ProfileStore.shared.demo()
        AutomationStore.shared.demo()
        monitor.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            DemoMode.fakeMachine(monitor)
            func out(_ name: String) -> URL { dir.appendingPathComponent(name + ".png") }
            @MainActor func popover(_ tab: Tab, query: String = "") -> some View {
                let nav = PopoverState()
                nav.tab = tab
                let cs = ClipListState()
                cs.query = query
                return MainView(nav: nav, monitor: monitor, clipboard: clipboard, toolbox: toolbox, internet: internet,
                                notes: notes, cleaner: Cleaner(), updater: UpdaterModel(enabled: false), clipState: cs, onPickClip: { _, _ in })
            }
            let pop = NSSize(width: 400, height: 600)
            for tab in [Tab.now, .clipboard, .actions, .system] {
                Snapshot.render(popover(tab), size: pop, dark: true, to: out("popover-\(tab)"))
            }
            // Busca no clipboard, letra a letra
            let search = "github"
            for n in 1...search.count {
                Snapshot.render(popover(.clipboard, query: String(search.prefix(n))), size: pop, dark: true,
                                to: out("clip-search-\(n)"))
            }
            // Palette: duas consultas digitadas letra a letra
            let palette = PaletteModel(toolbox: toolbox, clipboard: clipboard, notes: notes)
            palette.isDemo = true
            palette.update()
            Snapshot.render(PaletteController.chrome(PaletteView(model: palette)), size: PaletteController.size, dark: true,
                            background: .clear, to: out("palette-0-0"))
            for (q, text) in ["5 km to mi", "timer 10m tea"].enumerated() {
                for n in 1...text.count {
                    palette.query = String(text.prefix(n))
                    Snapshot.render(PaletteController.chrome(PaletteView(model: palette)), size: PaletteController.size, dark: true,
                                    background: .clear, to: out("palette-\(q + 1)-\(n)"))
                }
            }
            // Notch ao passar o mouse: próxima reunião e atalhos
            let hm = NotchHoverModel()
            hm.shown = true
            hm.meeting = Meeting(id: "demo", title: L("Alinhamento semanal"), start: Date().addingTimeInterval(14 * 60),
                                 end: Date().addingTimeInterval(44 * 60), link: URL(string: "https://meet.example.com/abc"), color: .orange)
            hm.focusEnd = Date().addingTimeInterval(18 * 60)
            hm.after = Meeting(id: "d3", title: L("Revisão do trimestre"), start: Date().addingTimeInterval(3 * 3600),
                               end: Date().addingTimeInterval(4 * 3600), link: nil, color: .purple)
            Snapshot.render(NotchHoverView(model: hm, notch: CGSize(width: 200, height: 37)).frame(width: 480, height: 172),
                            size: NSSize(width: 480, height: 172), dark: true, background: .clear, to: out("notch"))
            print("Video frames saved to \(dir.path)")
            exit(0)
        }
    }
}
