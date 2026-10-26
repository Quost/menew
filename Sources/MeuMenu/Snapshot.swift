import AppKit
import SwiftUI

/// `MeuMenu --snapshot <pasta>`: renderiza as telas em PNG (claro e escuro) e sai.
/// Usa um histórico fictício, nunca o clipboard real.
@MainActor
enum Snapshot {
    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let monitor = SystemMonitor()
        let clipboard = ClipboardManager.demo()
        let toolbox = Toolbox()
        let internet = InternetInfo()
        internet.speed = .done(SpeedResult(down: 224, up: 146, latency: 21, rpm: 425))
        internet.publicIP = "189.0.113.42"
        internet.devices = [
            BTDevice(name: "AirPods Pro", kind: .airpods, levels: [("E", 90), ("D", 88), ("Estojo", 54)]),
            BTDevice(name: "Magic Mouse", kind: .mouse, levels: [("", 17)]),
        ]
        let notes = NotesStore(dir: FileManager.default.temporaryDirectory)
        notes.text = "Ideias pro MeuMenu\n- snippets de texto\n- atalhos configuráveis\n\nLigar pro João às 16h"
        monitor.start()

        // Espera alguns ciclos para CPU/rede terem dados
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            monitor.topProcesses = monitor.topProcesses.isEmpty
                ? [ProcInfo(name: "WindowServer", cpu: 12, memKB: 400_000)] : monitor.topProcesses
            for dark in [false, true] {
                let suffix = dark ? "dark" : "light"
                for tab in Tab.allCases {
                    let nav = PopoverState()
                    nav.tab = tab
                    let v = MainView(nav: nav, monitor: monitor, clipboard: clipboard, toolbox: toolbox, internet: internet,
                                     notes: notes, clipState: ClipListState(), onPickClip: { _, _ in })
                    render(v, size: NSSize(width: 400, height: 600), dark: dark,
                           to: dir.appendingPathComponent("popover-\(tab)-\(suffix).png"))
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
            for style in MenuBarStyle.allCases {
                let segs: [StatusSegment]
                switch style {
                case .icon: segs = []
                case .cpu: segs = [.stat("CPU", "23%")]
                case .cpuRam: segs = [.stat("CPU", "23%"), .stat("RAM", "64%")]
                case .network: segs = [.net("1.2M", "48K")]
                case .all: segs = [.stat("CPU", "23%"), .stat("RAM", "64%"), .net("1.2M", "48K")]
                }
                let img = StatusRenderer.image(segments: segs)
                let v = Image(nsImage: img).padding(.horizontal, 8).frame(height: 24)
                render(v, size: NSSize(width: img.size.width + 16, height: 24), dark: false,
                       background: NSColor(white: 0.93, alpha: 1), scale: 4,
                       to: dir.appendingPathComponent("statusbar-\(style).png"))
            }
            NSApp.terminate(nil)
        }
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
