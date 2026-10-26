import AppKit
import Carbon
import SwiftUI

@main
@MainActor
enum MeuMenuMain {
    static let delegate = AppDelegate()
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = SystemMonitor()
    let clipboard = ClipboardManager()
    let toolbox = Toolbox()
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
            let img = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "MeuMenu")
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MainView(
            nav: nav, monitor: monitor, clipboard: clipboard, toolbox: toolbox, clipState: popoverClipState,
            onPickClip: { [weak self] item, plain in self?.pickFromPopover(item, plain: plain) }
        ))

        monitor.onTick = { [weak self] in self?.updateStatusTitle() }
        monitor.start()
        clipboard.start()

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusTitle() }
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

    // MARK: Barra de menus

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        let style = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "") ?? .cpuRam
        let cpu = "CPU \(Fmt.pct(monitor.cpu))"
        let ram = "RAM \(Fmt.pct(monitor.memFraction))"
        let net = "↓\(Fmt.shortRate(monitor.netIn)) ↑\(Fmt.shortRate(monitor.netOut))"
        let text: String
        switch style {
        case .icon: text = ""
        case .cpu: text = cpu
        case .cpuRam: text = "\(cpu)  \(ram)"
        case .network: text = net
        case .all: text = "\(cpu)  \(ram)  \(net)"
        }
        let title = text.isEmpty ? "" : " " + text
        if button.title != title {
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .baselineOffset: 0.5,
            ])
        }
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
        func add(_ title: String, _ key: String = "", _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        add("Histórico do clipboard (⌘⇧V)", "", #selector(openClipPanel))
        add("Ajustes…", ",", #selector(openSettings))
        menu.addItem(.separator())
        add("Sair do MeuMenu", "q", #selector(quit))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openClipPanel() { clipPanel.show() }
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
