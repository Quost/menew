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
        } else {
            app.delegate = delegate
        }
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = SystemMonitor()
    let clipboard = ClipboardManager()
    let toolbox = Toolbox()
    let internet = InternetInfo()
    lazy var notes = NotesStore(dir: clipboard.dir)
    let nav = PopoverState()
    let popoverClipState = ClipListState()
    lazy var clipPanel = ClipboardPanelController(manager: clipboard)

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKeys: [HotKey] = []
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "menuBarStyle": MenuBarStyle.cpuRam.rawValue,
            "autoPaste": true,
            "maxItems": 300,
            "ignoreConcealed": true,
        ])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MainView(
            nav: nav, monitor: monitor, clipboard: clipboard, toolbox: toolbox, internet: internet, notes: notes,
            clipState: popoverClipState,
            onPickClip: { [weak self] item, plain in self?.pickFromPopover(item, plain: plain) }
        ))

        monitor.onTick = { [weak self] in self?.updateStatusItem() }
        monitor.start()
        clipboard.start()
        updateStatusItem()

        applyAppearance()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusItem()
                self?.applyAppearance()
            }
        }

        hotKeys = [
            HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), id: 1) { [weak self] in
                MainActor.assumeIsolated { self?.clipPanel.toggle() }
            },
            HotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | optionKey), id: 2) { [weak self] in
                MainActor.assumeIsolated { self?.togglePopover() }
            },
        ]
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
        let style = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "") ?? .cpuRam
        var segments: [StatusSegment] = []
        switch style {
        case .icon: break
        case .cpu: segments = [.stat("CPU", Fmt.pct(monitor.cpu))]
        case .cpuRam: segments = [.stat("CPU", Fmt.pct(monitor.cpu)), .stat("RAM", Fmt.pct(monitor.memFraction))]
        case .network: segments = [.net(Fmt.shortRate(monitor.netIn), Fmt.shortRate(monitor.netOut))]
        case .all: segments = [.stat("CPU", Fmt.pct(monitor.cpu)), .stat("RAM", Fmt.pct(monitor.memFraction)),
                               .net(Fmt.shortRate(monitor.netIn), Fmt.shortRate(monitor.netOut))]
        }
        let key = segments.map(\.key).joined(separator: "|")
        guard key != lastStatusKey || button.image == nil else { return }
        lastStatusKey = key
        button.image = StatusRenderer.image(segments: segments)
        button.imagePosition = .imageOnly
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
        add("Histórico do clipboard", "", "doc.on.clipboard", #selector(openClipPanel))
        add("Limpar teclado", "", "keyboard", #selector(lockKeyboard))
        add("Limpar tela", "", "sparkles.tv", #selector(blackScreen))
        menu.addItem(.separator())
        add("Ajustes…", ",", "gearshape", #selector(openSettings))
        add("Sair do Menew", "q", "power", #selector(quit))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openClipPanel() { clipPanel.show() }
    @objc private func lockKeyboard() { toolbox.cleaning.lockKeyboard() }
    @objc private func blackScreen() { toolbox.cleaning.blackScreen() }
    @objc private func openSettings() { nav.tab = .settings; showPopover() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        popoverClipState.query = ""
        popoverClipState.focusToken += 1
        NSApp.activate(ignoringOtherApps: true)
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

    var key: String {
        switch self {
        case .stat(let a, let b): "\(a)\(b)"
        case .net(let a, let b): "\(a)\(b)"
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
                }
                x += w + gap
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
