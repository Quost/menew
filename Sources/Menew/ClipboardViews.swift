import AppKit
import SwiftUI

@MainActor
final class ClipListState: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { selection = 0 } } }
    @Published var filter: ClipFilter = .all { didSet { if filter != oldValue { selection = 0 } } }
    @Published var selection = 0
    @Published var focusToken = 0
}

// MARK: Peças compartilhadas

struct SearchField: View {
    @ObservedObject var state: ClipListState
    var large = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: large ? 17 : 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(L("Buscar no histórico"), text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: large ? 19 : 13))
                .frame(height: large ? 30 : 18)
                .focused($focused)
            if !state.query.isEmpty {
                Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
            if UserDefaults.standard.bool(forKey: "paused") {
                Label(L("Pausado"), systemImage: "pause.circle.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, large ? 4 : 10)
        .padding(.vertical, large ? 0 : 7)
        .background {
            if !large { RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)) }
        }
        .onAppear { focused = true }
        .onChange(of: state.focusToken) { _, _ in focused = true }
    }
}

struct FilterChips: View {
    @ObservedObject var state: ClipListState
    var iconsOnly = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ClipFilter.allCases, id: \.self) { f in
                let on = state.filter == f
                Button { state.filter = f } label: {
                    HStack(spacing: 4) {
                        Image(systemName: f.icon).font(.system(size: 10, weight: .semibold))
                        if !iconsOnly || on { Text(f.label) }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 4.5)
                    .background(Capsule().fill(on ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.06))))
                    .foregroundStyle(on ? Color.white : Color.secondary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ClipThumb: View {
    let item: ClipItem
    let manager: ClipboardManager
    var size: CGFloat = 32

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                if let img = manager.thumbnail(for: item) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    tile("photo", .teal)
                }
            case .file:
                if let p = item.text?.split(separator: "\n").first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: String(p))).resizable().padding(1)
                }
            case .text:
                if let c = item.hexColor {
                    Color(nsColor: c)
                } else if item.url != nil {
                    tile("link", .blue)
                } else if let icon = AppIcons.icon(for: item.sourceBundle) {
                    Image(nsImage: icon).resizable().padding(1)
                } else {
                    tile("text.alignleft", .gray)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay {
            if item.hexColor != nil || item.kind == .image {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
        }
    }

    private func tile(_ icon: String, _ color: Color) -> some View {
        ZStack {
            Rectangle().fill(color.gradient)
            Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let manager: ClipboardManager

    var body: some View {
        HStack(spacing: 10) {
            ClipThumb(item: item, manager: manager)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind == .file ? fileTitle : item.kind == .image ? item.title.replacingOccurrences(of: "Imagem", with: L("Imagem")) : item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 11))
                    .opacity(0.65)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).rotationEffect(.degrees(35))
                    .foregroundStyle(selected ? Color.white : Color.orange)
            }
            if index < 9 {
                Text("⌘\(index + 1)").font(.system(size: 10.5, weight: .medium, design: .rounded)).opacity(0.5)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background {
            if selected { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.brand) }
        }
        .contentShape(Rectangle())
    }

    private var fileTitle: String {
        let paths = (item.text ?? "").split(separator: "\n")
        let first = (paths.first.map { String($0) } ?? "") as NSString
        return paths.count > 1 ? L("%@ e mais %d", first.lastPathComponent, paths.count - 1) : first.lastPathComponent
    }

    private var meta: String {
        [item.sourceApp, RelDate.string(item.date)].compactMap { $0 }.joined(separator: " · ")
    }
}

struct ClipList: View {
    @ObservedObject var manager: ClipboardManager
    @ObservedObject var state: ClipListState
    let list: [ClipItem]
    var onActivate: (ClipItem, Bool) -> Void

    var body: some View {
        if list.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: state.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                Text(state.query.isEmpty ? L("Copie algo para começar") : L("Nada encontrado"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { idx, item in
                            ClipRow(item: item, index: idx, selected: idx == state.selection, manager: manager)
                                .id(item.id)
                                .onTapGesture { onActivate(item, false) }
                                .onHover { if $0 { state.selection = idx } }
                                .contextMenu { ClipContextMenu(item: item, manager: manager, onActivate: onActivate) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: state.selection) { _, new in
                    if list.indices.contains(new) { proxy.scrollTo(list[new].id) }
                }
            }
        }
    }
}

struct ClipContextMenu: View {
    let item: ClipItem
    let manager: ClipboardManager
    var onActivate: (ClipItem, Bool) -> Void

    var body: some View {
        Button(L("Colar")) { onActivate(item, false) }
        if item.kind == .text { Button(L("Colar como texto puro")) { onActivate(item, true) } }
        Button(L("Só copiar")) { manager.copy(item) }
        Button(item.pinned ? L("Desafixar") : L("Fixar")) { manager.togglePin(item) }
        if item.kind == .text, let t = item.text {
            Menu(L("Transformar e copiar")) {
                Button(L("MAIÚSCULAS")) { manager.copyText(t.uppercased()) }
                Button(L("minúsculas")) { manager.copyText(t.lowercased()) }
                Button(L("Primeira Letra Maiúscula")) { manager.copyText(t.capitalized) }
                Button(L("Remover espaços extras")) {
                    manager.copyText(t.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                }
            }
        }
        if let u = item.url { Button(L("Abrir link")) { NSWorkspace.shared.open(u) } }
        if item.kind == .file, let p = item.text?.split(separator: "\n").first {
            Button(L("Mostrar no Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: String(p))])
            }
        }
        if item.kind == .image, let u = manager.imageURL(for: item) {
            Button(L("Abrir imagem")) { NSWorkspace.shared.open(u) }
        }
        Divider()
        Button(L("Apagar"), role: .destructive) { manager.delete(item) }
    }
}

// MARK: Pré-visualização

struct ClipPreview: View {
    let item: ClipItem
    @ObservedObject var manager: ClipboardManager
    var onActivate: (ClipItem, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 7) {
                infoRow(L("Origem")) {
                    HStack(spacing: 5) {
                        if let icon = AppIcons.icon(for: item.sourceBundle) {
                            Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                        }
                        Text(item.sourceApp ?? L("Desconhecido"))
                    }
                }
                infoRow(L("Copiado")) { Text(item.date.formatted(.dateTime.day().month().hour().minute().locale(L10n.locale))) }
                infoRow(L("Conteúdo")) { Text(stats) }
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 18).padding(.vertical, 12)

            HStack(spacing: 8) {
                PillButton(title: L("Colar"), icon: "arrow.turn.down.left", primary: true) { onActivate(item, false) }
                PillButton(title: L("Copiar"), icon: "doc.on.doc") { manager.copy(item) }
                PillButton(title: item.pinned ? L("Desafixar") : L("Fixar"), icon: item.pinned ? "pin.slash" : "pin") { manager.togglePin(item) }
                Spacer()
                IconButton(icon: "trash", help: L("Apagar")) { manager.delete(item) }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let img = manager.thumbnail(for: item) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxHeight: 260)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark").font(.system(size: 30, weight: .light))
                    Text(L("O arquivo desta imagem não foi encontrado.")).font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        case .file:
            VStack(alignment: .leading, spacing: 10) {
                ForEach((item.text ?? "").split(separator: "\n").prefix(20).map(String.init), id: \.self) { path in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((path as NSString).lastPathComponent).font(.system(size: 13, weight: .medium))
                            Text((path as NSString).deletingLastPathComponent).font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
        case .text:
            if let c = item.hexColor?.usingColorSpace(.sRGB) {
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: c)).frame(height: 140)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
                    Text(item.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "")
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    Text("RGB \(Int(c.redComponent * 255)), \(Int(c.greenComponent * 255)), \(Int(c.blueComponent * 255))")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
            } else if let u = item.url {
                VStack(alignment: .leading, spacing: 8) {
                    Label(u.host() ?? L("Link"), systemImage: "globe").font(.system(size: 15, weight: .semibold))
                    Text(u.absoluteString).font(.system(size: 13)).foregroundStyle(.blue).textSelection(.enabled)
                    PillButton(title: L("Abrir no navegador"), icon: "arrow.up.right") { NSWorkspace.shared.open(u) }
                        .padding(.top, 4)
                }
            } else {
                Text(String((item.text ?? "").prefix(20_000)))
                    .font(.system(size: 13, design: item.isCode ? .monospaced : .default))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
    }

    private var stats: String {
        switch item.kind {
        case .image: return (item.text ?? "Imagem").replacingOccurrences(of: "Imagem", with: L("Imagem"))
        case .file:
            let n = (item.text ?? "").split(separator: "\n").count
            return n == 1 ? L("1 arquivo") : L("%d arquivos", n)
        case .text:
            let t = item.text ?? ""
            let words = t.split(whereSeparator: \.isWhitespace).count
            let lines = t.split(separator: "\n", omittingEmptySubsequences: false).count
            return L(lines == 1 ? "%d caracteres · %d palavras · %d linha" : "%d caracteres · %d palavras · %d linhas", t.count, words, lines)
        }
    }

    private func infoRow<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            value()
            Spacer()
        }
    }
}

// MARK: Painel flutuante (⌘⇧V)

struct ClipboardPanelView: View {
    @ObservedObject var manager: ClipboardManager
    @ObservedObject var state: ClipListState
    var onActivate: (ClipItem, Bool) -> Void
    @AppStorage("language") private var language = "auto"

    var body: some View {
        let list = manager.filtered(state.query, state.filter)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                SearchField(state: state, large: true)
                FilterChips(state: state)
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 12)

            Divider().opacity(0.6)

            HStack(spacing: 0) {
                ClipList(manager: manager, state: state, list: list, onActivate: onActivate)
                    .frame(width: 330)
                Divider().opacity(0.6)
                Group {
                    if list.indices.contains(state.selection) {
                        ClipPreview(item: list[state.selection], manager: manager, onActivate: onActivate)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Divider().opacity(0.6)
            HStack(spacing: 14) {
                hint("↩", L("colar"))
                hint("⌥↩", L("texto puro"))
                hint("⌘1–9", L("rápido"))
                hint("⌘P", L("fixar"))
                hint("⌘⌫", L("apagar"))
                Spacer()
                Text(L("%d itens", manager.items.count)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 16).padding(.vertical, 9)
        }
        .id(language)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Keycap(text: key)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

/// Versão compacta, dentro do popover
struct ClipboardTabView: View {
    @ObservedObject var manager: ClipboardManager
    @ObservedObject var state: ClipListState
    var onActivate: (ClipItem, Bool) -> Void

    var body: some View {
        VStack(spacing: 10) {
            SearchField(state: state)
            FilterChips(state: state, iconsOnly: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ClipList(manager: manager, state: state, list: manager.filtered(state.query, state.filter), onActivate: onActivate)
                .padding(.horizontal, -6)
        }
        .padding(.horizontal, 12).padding(.top, 4)
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

    private static var byName: [String: NSImage?] = [:]
    /// Ícone de um processo pelo nome do executável (para a lista de processos)
    static func icon(forProcess name: String) -> NSImage? {
        if let c = byName[name] { return c }
        let app = NSWorkspace.shared.runningApplications.first {
            $0.executableURL?.lastPathComponent == name || $0.localizedName == name
        }
        let img = app?.icon
        byName[name] = img
        return img
    }
}

// MARK: Janela do painel

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
        state.filter = .all
        state.selection = 0

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + vf.height * 0.6 - size.height / 2))
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
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
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
                         styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self

        let root = ClipboardPanelView(manager: manager, state: state) { [weak self] item, plain in
            self?.activate(item, plain: plain)
        }
        .frame(width: 780, height: 500)
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        p.contentView = NSHostingView(rootView: root)
        return p
    }

    private func activate(_ item: ClipItem, plain: Bool) {
        close()
        manager.paste(item, plainText: plain)
    }

    private func installMonitor() {
        if monitor != nil { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            nonisolated(unsafe) let e = event
            return MainActor.assumeIsolated {
                guard let self, e.window === self.panel else { return e }
                return self.handle(e) ? nil : e
            }
        }
    }

    /// true = evento consumido
    private func handle(_ e: NSEvent) -> Bool {
        let list = manager.filtered(state.query, state.filter)
        let cmd = e.modifierFlags.contains(.command)
        let opt = e.modifierFlags.contains(.option)
        switch e.keyCode {
        case 53: close(); return true                                       // esc
        case 125: state.selection = min(state.selection + 1, max(list.count - 1, 0)); return true // ↓
        case 126: state.selection = max(state.selection - 1, 0); return true // ↑
        case 48:                                                             // tab: próximo filtro
            let all = ClipFilter.allCases
            let i = all.firstIndex(of: state.filter) ?? 0
            state.filter = all[(i + (e.modifierFlags.contains(.shift) ? all.count - 1 : 1)) % all.count]
            return true
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
