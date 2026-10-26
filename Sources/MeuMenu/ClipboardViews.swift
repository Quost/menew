import AppKit
import SwiftUI

@MainActor
final class ClipListState: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { selection = 0 } } }
    @Published var selection = 0
    @Published var focusToken = 0
}

/// Lista com busca, usada tanto no painel flutuante (⌘⇧V) quanto no popover
struct ClipboardListView: View {
    @ObservedObject var manager: ClipboardManager
    @ObservedObject var state: ClipListState
    var compact = false
    var onActivate: (ClipItem, Bool) -> Void   // (item, textoPuro)

    @FocusState private var searchFocused: Bool

    var body: some View {
        let list = manager.filtered(state.query)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar no histórico…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: compact ? 13 : 16))
                    .focused($searchFocused)
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                if UserDefaults.standard.bool(forKey: "paused") {
                    Label("Pausado", systemImage: "pause.circle.fill").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, compact ? 8 : 12)

            Divider()

            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(state.query.isEmpty ? "Copie algo para começar" : "Nada encontrado")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { idx, item in
                                ClipRow(item: item, index: idx, selected: idx == state.selection, manager: manager)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivate(item, false) }
                                    .onHover { if $0 { state.selection = idx } }
                                    .contextMenu { contextMenu(for: item) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: state.selection) { _, new in
                        if list.indices.contains(new) { proxy.scrollTo(list[new].id) }
                    }
                }
            }

            if !compact {
                Divider()
                HStack(spacing: 14) {
                    hint("↩", "colar")
                    hint("⌥↩", "texto puro")
                    hint("⌘1-9", "rápido")
                    hint("⌘P", "fixar")
                    hint("⌘⌫", "apagar")
                    Spacer()
                    Text("\(manager.items.count) itens").foregroundStyle(.tertiary)
                }
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 7)
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: state.focusToken) { _, _ in searchFocused = true }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.caption.monospaced()).padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            Text(label).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button("Colar") { onActivate(item, false) }
        if item.kind == .text { Button("Colar como texto puro") { onActivate(item, true) } }
        Button("Só copiar") { manager.copy(item) }
        Button(item.pinned ? "Desafixar" : "Fixar") { manager.togglePin(item) }
        if item.kind == .text, let t = item.text {
            Menu("Transformar e copiar") {
                Button("MAIÚSCULAS") { manager.copyText(t.uppercased()) }
                Button("minúsculas") { manager.copyText(t.lowercased()) }
                Button("Primeira Letra Maiúscula") { manager.copyText(t.capitalized) }
                Button("Remover espaços extras") {
                    manager.copyText(t.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                }
                Button("Contar caracteres") {
                    let words = t.split(whereSeparator: \.isWhitespace).count
                    manager.copyText("\(t.count) caracteres, \(words) palavras")
                }
            }
        }
        if let u = item.url { Button("Abrir link") { NSWorkspace.shared.open(u) } }
        if item.kind == .file, let p = item.text?.split(separator: "\n").first {
            Button("Mostrar no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: String(p))])
            }
        }
        if item.kind == .image, let u = manager.imageURL(for: item) {
            Button("Abrir imagem") { NSWorkspace.shared.open(u) }
        }
        Divider()
        Button("Apagar", role: .destructive) { manager.delete(item) }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let manager: ClipboardManager

    var body: some View {
        HStack(spacing: 10) {
            leading.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .lineLimit(2)
                    .font(.system(size: 12.5))
                HStack(spacing: 6) {
                    if let app = item.sourceApp { Text(app) }
                    Text(item.date, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if item.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
            if index < 9 {
                Text("⌘\(index + 1)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.22) : .clear))
    }

    @ViewBuilder private var leading: some View {
        switch item.kind {
        case .image:
            if let img = manager.thumbnail(for: item) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: "photo")
            }
        case .file:
            if let p = item.text?.split(separator: "\n").first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: String(p))).resizable()
            }
        case .text:
            if let c = item.hexColor {
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: c))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            } else if item.url != nil {
                Image(systemName: "link").font(.system(size: 15)).foregroundStyle(.blue)
            } else if let icon = AppIcons.icon(for: item.sourceBundle) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "text.alignleft").foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(for bundle: String?) -> NSImage? {
        guard let bundle else { return nil }
        if let c = cache[bundle] { return c }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundle] = img
        return img
    }
}

// MARK: Painel flutuante (⌘⇧V)

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    let manager: ClipboardManager
    let state = ClipListState()
    private var panel: KeyPanel?
    private var monitor: Any?

    init(manager: ClipboardManager) {
        self.manager = manager
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? close() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        state.query = ""
        state.selection = 0

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + vf.height * 0.62 - size.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        state.focusToken += 1
        installMonitor()
    }

    func close() {
        panel?.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func makePanel() -> KeyPanel {
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 470),
                         styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { p.standardWindowButton($0)?.isHidden = true }

        let root = ClipboardListView(manager: manager, state: state) { [weak self] item, plain in
            self?.activate(item, plain: plain)
        }
        .frame(minWidth: 600, minHeight: 470)
        .background(VisualEffect(material: .hudWindow))
        let host = NSHostingView(rootView: root)
        p.contentView = host
        return p
    }

    private func activate(_ item: ClipItem, plain: Bool) {
        close()
        manager.paste(item, plainText: plain)
    }

    private func installMonitor() {
        if monitor != nil { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.panel else { return event }
                return self.handle(event) ? nil : event
            }
        }
    }

    /// true = evento consumido
    private func handle(_ e: NSEvent) -> Bool {
        let list = manager.filtered(state.query)
        let cmd = e.modifierFlags.contains(.command)
        let opt = e.modifierFlags.contains(.option)
        switch e.keyCode {
        case 53: close(); return true                                       // esc
        case 125: state.selection = min(state.selection + 1, max(list.count - 1, 0)); return true // ↓
        case 126: state.selection = max(state.selection - 1, 0); return true // ↑
        case 36, 76:                                                         // return / enter
            if list.indices.contains(state.selection) { activate(list[state.selection], plain: opt) }
            return true
        case 51 where cmd:                                                   // ⌘⌫
            if list.indices.contains(state.selection) { manager.delete(list[state.selection]) }
            return true
        default: break
        }
        if cmd, let ch = e.charactersIgnoringModifiers?.lowercased() {
            if let n = Int(ch), (1...9).contains(n) {
                if list.indices.contains(n - 1) { activate(list[n - 1], plain: opt) }
                return true
            }
            if ch == "p", list.indices.contains(state.selection) {
                manager.togglePin(list[state.selection]); return true
            }
            if ch == "w" { close(); return true }
        }
        return false
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}
