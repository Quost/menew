import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: Itens

/// Algo guardado na estante. Arquivos ficam só como referência (nada é copiado nem movido).
struct ShelfItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case file(URL)
        case link(URL)
        case text(String)
    }

    let id = UUID()
    let kind: Kind

    var title: String {
        switch kind {
        case .file(let u): FileManager.default.displayName(atPath: u.path)
        case .link(let u): u.host() ?? u.absoluteString
        case .text(let t): t.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? t
        }
    }

    var subtitle: String {
        switch kind {
        case .file(let u):
            let values = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
            if u.pathExtension == "app" { return L("App") }
            if values?.isDirectory == true && values?.isPackage != true { return L("Pasta") }
            return values?.fileSize.map { Fmt.bytes(Int64($0)) } ?? u.deletingLastPathComponent().lastPathComponent
        case .link(let u): return u.absoluteString
        case .text(let t): return L("%d caracteres", t.count)
        }
    }

    @MainActor var icon: NSImage {
        switch kind {
        case .file(let u):
            FileManager.default.fileExists(atPath: u.path) ? NSWorkspace.shared.icon(forFile: u.path)
                : NSWorkspace.shared.icon(for: UTType(filenameExtension: u.pathExtension) ?? .data)
        case .link: NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        case .text: NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil) ?? NSImage()
        }
    }

    var isFile: Bool { if case .file = kind { true } else { false } }

    /// O que vai junto quando o item é arrastado para outro app
    var writer: NSPasteboardWriting {
        switch kind {
        case .file(let u), .link(let u): u as NSURL
        case .text(let t): t as NSString
        }
    }
}

// MARK: Estado

@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    @Published private(set) var items: [ShelfItem] = []
    @Published var targeted = false

    /// Imagens soltas sem arquivo (de um navegador, por exemplo) viram PNG numa pasta temporária
    private lazy var tempDir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("MenewShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func add(_ new: [ShelfItem]) {
        for item in new where !items.contains(where: { $0.kind == item.kind }) { items.append(item) }
    }

    func remove(_ item: ShelfItem) { items.removeAll { $0.id == item.id } }

    func clear() { items = [] }

    func demo() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        items = [
            ShelfItem(kind: .file(home.appendingPathComponent("Desktop/Proposta.pdf"))),
            ShelfItem(kind: .file(URL(fileURLWithPath: "/System/Applications/Notes.app"))),
            ShelfItem(kind: .link(URL(string: "https://github.com/Quost/menew")!)),
            ShelfItem(kind: .text(L("Reunião de alinhamento movida para quinta às 14h"))),
        ]
    }

    /// Lê o que foi solto: arquivos, links, imagens e texto
    func accept(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in self.add([ShelfItem(kind: .file(url))]) }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in self.add([ShelfItem(kind: .link(url))]) }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in self.saveImage(data) }
                }
            } else if p.canLoadObject(ofClass: String.self) {
                accepted = true
                _ = p.loadObject(ofClass: String.self) { text, _ in
                    guard let text, !text.isEmpty else { return }
                    Task { @MainActor in
                        // Um link colado como texto continua sendo um link
                        if let u = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme?.hasPrefix("http") == true {
                            self.add([ShelfItem(kind: .link(u))])
                        } else {
                            self.add([ShelfItem(kind: .text(text))])
                        }
                    }
                }
            }
        }
        return accepted
    }

    private func saveImage(_ data: Data) {
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let name = L("Imagem") + " " + Date().formatted(.dateTime.hour().minute().second()).replacingOccurrences(of: ":", with: ".")
        let url = tempDir.appendingPathComponent(name).appendingPathExtension("png")
        guard (try? png.write(to: url)) != nil else { return }
        add([ShelfItem(kind: .file(url))])
    }

    // MARK: Ações dos itens

    func copy(_ item: ShelfItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.writer])
    }

    func open(_ item: ShelfItem) {
        switch item.kind {
        case .file(let u), .link(let u): NSWorkspace.shared.open(u)
        case .text: copy(item)
        }
    }

    func reveal(_ item: ShelfItem) {
        if case .file(let u) = item.kind { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }
}

// MARK: Arrastar para fora

/// Área que começa a arrastar os itens. Sempre como cópia: o arquivo original nunca é movido.
final class ShelfDragView: NSView, NSDraggingSource {
    var items: () -> [ShelfItem] = { [] }
    var onDoubleClick: () -> Void = {}
    var menuItems: () -> [NSMenuItem] = { [] }
    private var downEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2 { onDoubleClick() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        downEvent = nil
        let list = items()
        guard !list.isEmpty else { return }
        let origin = convert(down.locationInWindow, from: nil)
        let drag = list.enumerated().map { i, item -> NSDraggingItem in
            let d = NSDraggingItem(pasteboardWriter: item.writer)
            let icon = MainActor.assumeIsolated { item.icon }
            d.setDraggingFrame(NSRect(x: origin.x - 16 + CGFloat(i * 4), y: origin.y - 16 - CGFloat(i * 4), width: 32, height: 32),
                               contents: icon)
            return d
        }
        beginDraggingSession(with: drag, event: down, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let list = menuItems()
        guard !list.isEmpty else { return nil }
        let menu = NSMenu()
        list.forEach(menu.addItem)
        return menu
    }
}

/// Menu de contexto feito de closures (NSMenuItem precisa de target/action)
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

struct ShelfDragArea: NSViewRepresentable {
    let items: () -> [ShelfItem]
    var onDoubleClick: () -> Void = {}
    var menuItems: () -> [NSMenuItem] = { [] }

    func makeNSView(context: Context) -> ShelfDragView { ShelfDragView() }

    func updateNSView(_ v: ShelfDragView, context: Context) {
        v.items = items
        v.onDoubleClick = onDoubleClick
        v.menuItems = menuItems
    }
}

// MARK: Tela

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    var onClose: () -> Void
    @AppStorage("language") private var language = "auto"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill").foregroundStyle(Theme.indigo)
                Text(L("Estante")).font(.system(size: 13, weight: .semibold))
                if !store.items.isEmpty {
                    Text("\(store.items.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                if !store.items.isEmpty {
                    IconButton(icon: "trash", help: L("Esvaziar estante")) { store.clear() }
                }
                IconButton(icon: "xmark", help: L("Fechar (os itens continuam aqui)")) { onClose() }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)

            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 26, weight: .light))
                    Text(L("Solte arquivos, links ou textos aqui")).font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(store.targeted ? Theme.indigo : Color.primary.opacity(0.2)))
                .padding(.horizontal, 12).padding(.bottom, 12)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.items) { item in ShelfRow(item: item, store: store) }
                    }
                    .padding(.horizontal, 6)
                }
                .scrollIndicators(.never)

                // Puxa todos de uma vez
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw.fill")
                    Text(store.items.count == 1 ? L("Arraste para levar") : L("Arraste para levar os %d", store.items.count))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(Capsule().fill(Theme.indigo.gradient))
                .overlay(ShelfDragArea(items: { store.items }))
                .padding(10)
                .help(L("Arrasta todos os itens juntos para outro app ou pasta. Os originais ficam onde estão."))
            }
        }
        .background(store.targeted ? Theme.indigo.opacity(0.08) : .clear)
        .onDrop(of: [.fileURL, .url, .image, .plainText], isTargeted: $store.targeted) { store.accept($0) }
        .id(language)
    }
}

struct ShelfRow: View {
    let item: ShelfItem
    @ObservedObject var store: ShelfStore
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: item.icon).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(item.subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay(ShelfDragArea(items: { [item] }, onDoubleClick: { store.open(item) }, menuItems: { menu }))
            if hover {
                Button { store.remove(item) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                    .help(L("Tirar da estante"))
                    .accessibilityLabel(L("Tirar da estante"))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Color.primary.opacity(0.06) : .clear))
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
    }

    private var menu: [NSMenuItem] {
        var list = [ClosureMenuItem(item.isFile ? L("Abrir") : L("Copiar")) { store.open(item) }]
        if item.isFile {
            list.append(ClosureMenuItem(L("Mostrar no Finder")) { store.reveal(item) })
            list.append(ClosureMenuItem(L("Copiar")) { store.copy(item) })
        } else if case .link = item.kind {
            list.append(ClosureMenuItem(L("Copiar")) { store.copy(item) })
        }
        list.append(ClosureMenuItem(L("Tirar da estante")) { store.remove(item) })
        return list
    }
}

// MARK: Janela e gesto de chacoalhar

@MainActor
final class ShelfController: NSObject {
    static let shakeKey = "shelfShake"
    let store = ShelfStore.shared
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var dragChange = 0
    private var reversals: [TimeInterval] = []
    private var lastX: CGFloat?
    private var lastDir = 0
    private var openedByShake = false
    static let size = NSSize(width: 280, height: 340)

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? close() : show(nearMouse: false) }

    func show(nearMouse: Bool) {
        let p = panel ?? makePanel()
        panel = p
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            var origin = nearMouse ? NSPoint(x: mouse.x + 40, y: mouse.y - Self.size.height / 2)
                                   : NSPoint(x: vf.maxX - Self.size.width - 20, y: vf.midY - Self.size.height / 2)
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - Self.size.width - 8)
            origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - Self.size.height - 8)
            if !p.isVisible { p.setFrameOrigin(origin) }
        }
        p.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
        openedByShake = false
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: Self.chrome(ShelfView(store: store) { [weak self] in self?.close() }))
        return p
    }

    static func chrome<V: View>(_ v: V) -> some View {
        v.frame(width: size.width, height: size.height)
            .background(VisualEffect(material: .popover))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    /// Chacoalhar o mouse enquanto arrasta arquivos abre a estante perto do cursor
    func startShakeDetection() {
        let wanted = UserDefaults.standard.object(forKey: Self.shakeKey) as? Bool ?? true && Module.actions.isOn
        guard wanted != !monitors.isEmpty else { return } // já está como deveria
        stopShakeDetection()
        guard wanted else { close(); return }
        let drag = NSPasteboard(name: .drag)
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dragChange = drag.changeCount
                self?.reversals = []
                self?.lastX = nil
                self?.lastDir = 0
            }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dragged(drag) }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                // Abriu chacoalhando e o arquivo foi solto em outro lugar: some sozinha
                guard let self, self.openedByShake else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if self.openedByShake && self.store.items.isEmpty { self.close() }
                    self.openedByShake = false
                }
            }
        }) { monitors.append(m) }
    }

    func stopShakeDetection() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func dragged(_ drag: NSPasteboard) {
        // Só conta quando há um arrasto de arquivos de verdade (não seleção de texto, janela etc.)
        guard drag.changeCount != dragChange,
              drag.types?.contains(.fileURL) == true else { return }
        let x = NSEvent.mouseLocation.x
        defer { lastX = x }
        guard let lastX, abs(x - lastX) > 4 else { return }
        let dir = x > lastX ? 1 : -1
        if lastDir != 0, dir != lastDir {
            let now = ProcessInfo.processInfo.systemUptime
            reversals = reversals.filter { now - $0 < 0.6 } + [now]
            if reversals.count >= 3, !isVisible {
                reversals = []
                openedByShake = true
                show(nearMouse: true)
            }
        }
        lastDir = dir
    }
}
