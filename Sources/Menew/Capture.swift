import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

// MARK: Captura

/// Captura de tela com editor: área ou janela (espaço alterna, como no ⌘⇧4) ou a tela inteira.
/// Usa o `screencapture` do macOS; o arquivo temporário é apagado assim que a imagem abre no editor.
@MainActor
enum ScreenCapture {
    static let key = "shortcutCapture"
    private static var editors: [CaptureEditorController] = []
    private static var pins: [PinnedCapture] = []

    /// Sem a permissão de Gravação de Tela o `screencapture` mostra a mira mas não grava nada.
    /// Pede uma vez (o macOS mostra o aviso) e, se ainda faltar, explica onde ligar.
    static func hasAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if CGRequestScreenCaptureAccess() { return true }
        let alert = NSAlert()
        alert.messageText = L("Permita a Gravação de Tela")
        alert.informativeText = L("Para capturar a tela e copiar texto dela, ligue o Menew em Ajustes do Sistema → Privacidade e Segurança → Gravação de Tela e Áudio do Sistema. Depois reabra o Menew.")
        alert.addButton(withTitle: L("Abrir Ajustes"))
        alert.addButton(withTitle: L("Agora não"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    /// Área ou janela
    static func area() {
        guard hasAccess() else { return }
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        run(["-i", "-x"])
    }

    /// A tela onde está o mouse; espera o menu fechar antes
    static func fullScreen() {
        guard hasAccess() else { return }
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        let mouse = NSEvent.mouseLocation
        let index = (NSScreen.screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0) + 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { run(["-x", "-D", "\(index)"]) }
    }

    private static func run(_ args: [String]) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("menew-capture-\(UUID().uuidString).png")
        Task {
            let image: NSImage? = await Task.detached {
                Shell.run("/usr/sbin/screencapture", args + [file.path])
                defer { try? FileManager.default.removeItem(at: file) }
                // esc cancela e não cria o arquivo
                guard let data = try? Data(contentsOf: file) else { return nil }
                return NSImage(data: data)
            }.value
            if let image { edit(image) }
        }
    }

    static func edit(_ image: NSImage) {
        guard let doc = CaptureDocument(image: image) else { return }
        let c = CaptureEditorController(doc: doc)
        c.onClose = { [weak c] in editors.removeAll { $0 === c } }
        editors.append(c)
        c.show()
    }

    static func pin(_ image: NSImage) {
        let p = PinnedCapture(image: image)
        p.onClose = { [weak p] in pins.removeAll { $0 === p } }
        pins.append(p)
        p.show()
    }

    static func copy(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Captura copiada"))
    }

    static func save(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = L("Captura %@", Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second())
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")) + ".png"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let data = png(image) else { return }
        do {
            try data.write(to: url, options: .atomic)
            HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Captura salva"))
        } catch {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para salvar a captura"), duration: 2.5)
        }
    }

    static func png(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = image.size
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: Documento

struct CaptureMark: Identifiable, Equatable {
    enum Kind: String, CaseIterable { case arrow, rect, text, blur }
    var id = UUID()
    var kind: Kind
    /// Em pontos da imagem
    var a: CGPoint
    var b: CGPoint
    var color: Color
    var text = ""

    var rect: CGRect { CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)) }
}

@MainActor
final class CaptureDocument: ObservableObject {
    let image: CGImage
    /// A imagem toda pixelada, desenhada só dentro das áreas borradas
    let pixelated: CGImage
    /// Tamanho em pontos (a captura em tela Retina tem 2 pixels por ponto)
    let size: CGSize
    let scale: CGFloat
    @Published var marks: [CaptureMark] = []

    init?(image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.image = cg
        size = image.size.width > 0 ? image.size : CGSize(width: cg.width, height: cg.height)
        scale = CGFloat(cg.width) / size.width
        let ci = CIImage(cgImage: cg)
        let f = CIFilter.pixellate()
        f.inputImage = ci.clampedToExtent()
        f.scale = Float(max(10, CGFloat(cg.width) / 90))
        f.center = .zero
        let ctx = CIContext()
        pixelated = f.outputImage.flatMap { ctx.createCGImage($0, from: ci.extent) } ?? cg
    }

    /// Espessura das linhas proporcional à imagem, para seta e retângulo não sumirem em capturas grandes
    var lineWidth: CGFloat { max(3, min(size.width, size.height) / 160) }
    var fontSize: CGFloat { max(16, min(size.width, size.height) / 28) }

    /// A captura com as anotações, no tamanho original
    func render() -> NSImage {
        let renderer = ImageRenderer(content: CaptureCanvas(doc: self, marks: marks).frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return NSImage(cgImage: image, size: size) }
        return NSImage(cgImage: cg, size: size)
    }
}

/// Desenha a captura e as marcas; serve para a tela (reduzida) e para exportar (tamanho original)
struct CaptureCanvas: View {
    let doc: CaptureDocument
    let marks: [CaptureMark]

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / doc.size.width
            let full = CGRect(origin: .zero, size: size)
            ctx.draw(Image(decorative: doc.image, scale: 1), in: full)
            for m in marks {
                let r = CGRect(x: m.rect.minX * k, y: m.rect.minY * k, width: m.rect.width * k, height: m.rect.height * k)
                let lw = doc.lineWidth * k
                switch m.kind {
                case .blur:
                    ctx.drawLayer { layer in
                        layer.clip(to: Path(r))
                        layer.draw(Image(decorative: doc.pixelated, scale: 1), in: full)
                    }
                case .rect:
                    ctx.stroke(Path(roundedRect: r, cornerRadius: lw * 1.5), with: .color(m.color), lineWidth: lw)
                case .arrow:
                    let a = CGPoint(x: m.a.x * k, y: m.a.y * k), b = CGPoint(x: m.b.x * k, y: m.b.y * k)
                    let angle = atan2(b.y - a.y, b.x - a.x)
                    let head = lw * 4.5
                    var p = Path()
                    p.move(to: a)
                    p.addLine(to: b)
                    for side in [CGFloat.pi * 0.83, -CGFloat.pi * 0.83] {
                        p.move(to: b)
                        p.addLine(to: CGPoint(x: b.x + cos(angle + side) * head, y: b.y + sin(angle + side) * head))
                    }
                    ctx.stroke(p, with: .color(m.color), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                case .text:
                    let t = Text(m.text).font(.system(size: doc.fontSize * k, weight: .bold)).foregroundColor(m.color)
                    // Contorno escuro ou claro para ler sobre qualquer fundo
                    let outline: Color = m.color == .black ? .white : .black.opacity(0.55)
                    let o = max(1, lw / 3)
                    for (dx, dy) in [(-o, 0), (o, 0), (0, -o), (0, o)] {
                        ctx.draw(Text(m.text).font(.system(size: doc.fontSize * k, weight: .bold)).foregroundColor(outline),
                                 at: CGPoint(x: m.a.x * k + dx, y: m.a.y * k + dy), anchor: .topLeading)
                    }
                    ctx.draw(t, at: CGPoint(x: m.a.x * k, y: m.a.y * k), anchor: .topLeading)
                }
            }
        }
    }
}

// MARK: Editor

@MainActor
final class CaptureEditorController: NSObject, NSWindowDelegate {
    let doc: CaptureDocument
    var onClose: (() -> Void)?
    private var window: NSWindow?

    init(doc: CaptureDocument) { self.doc = doc }

    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let chrome: CGFloat = 104
        let fit = min(1, (vf.width * 0.8) / doc.size.width, (vf.height * 0.8 - chrome) / doc.size.height)
        let size = NSSize(width: max(620, doc.size.width * fit + 28), height: doc.size.height * fit + chrome)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        w.delegate = self
        w.contentView = NSHostingView(rootView: CaptureEditor(doc: doc) { [weak self] in self?.window?.close() })
        w.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2))
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

struct CaptureEditor: View {
    @ObservedObject var doc: CaptureDocument
    var close: () -> Void
    @State private var tool: CaptureMark.Kind = .arrow
    @State private var color: Color = .red
    @State private var draft: CaptureMark?
    @State private var typing: CaptureMark?
    @State private var typed = ""
    @FocusState private var textFocus: Bool

    private static let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            GeometryReader { geo in
                let k = min(geo.size.width / doc.size.width, geo.size.height / doc.size.height, 1)
                let shown = CGSize(width: doc.size.width * k, height: doc.size.height * k)
                ZStack(alignment: .topLeading) {
                    CaptureCanvas(doc: doc, marks: doc.marks + (draft.map { [$0] } ?? []))
                        .frame(width: shown.width, height: shown.height)
                        .gesture(drawing(k: k))
                    if let t = typing {
                        TextField(L("Texto"), text: $typed)
                            .textFieldStyle(.plain)
                            .font(.system(size: doc.fontSize * k, weight: .bold))
                            .foregroundStyle(t.color)
                            .focused($textFocus)
                            .frame(width: max(120, shown.width - t.a.x * k - 8), alignment: .leading)
                            .offset(x: t.a.x * k, y: t.a.y * k)
                            .onSubmit(commitText)
                    }
                }
                .frame(width: shown.width, height: shown.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            actions
        }
        .padding(.horizontal, 14).padding(.top, 30).padding(.bottom, 14)
        .background(VisualEffect(material: .popover).ignoresSafeArea())
        .onChange(of: textFocus) { _, focused in if !focused { commitText() } }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            GlassSegmented(selection: $tool, options: [
                .init(value: .arrow, icon: "arrow.up.right", help: L("Seta")),
                .init(value: .rect, icon: "rectangle", help: L("Retângulo")),
                .init(value: .text, icon: "textformat", help: L("Texto")),
                .init(value: .blur, icon: "checkerboard.rectangle", help: L("Borrar (esconde dados sensíveis)")),
            ], expand: false)
            HStack(spacing: 5) {
                ForEach(Self.colors, id: \.self) { c in
                    Button { color = c } label: {
                        Circle().fill(c).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                            .padding(2)
                            .overlay(Circle().strokeBorder(color == c ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(tool == .blur ? 0.35 : 1)
            .disabled(tool == .blur)
            Spacer(minLength: 4)
            IconButton(icon: "arrow.uturn.backward", help: L("Desfazer (⌘Z)")) { undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(doc.marks.isEmpty)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .help(L("Arraste para outro app"))
                .onDrag(dragProvider)
            Text(L("Arraste para outro app")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            PillButton(title: L("Copiar texto"), icon: "text.viewfinder") {
                let img = doc.image
                Task {
                    let text = await Task.detached { await TextRecognizer.recognize(img) }.value
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean.isEmpty { HUD.show(icon: "text.viewfinder", color: .orange, text: L("Nenhum texto encontrado")); return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(clean, forType: .string)
                    HUD.show(icon: "text.viewfinder", color: .green, text: L("Texto copiado"))
                }
            }
            PillButton(title: L("Fixar"), icon: "pin") { commitText(); ScreenCapture.pin(doc.render()); close() }
                .help(L("Deixa a captura flutuando sobre as janelas"))
            PillButton(title: L("Salvar…"), icon: "square.and.arrow.down") { commitText(); ScreenCapture.save(doc.render()) }
                .keyboardShortcut("s", modifiers: .command)
            PillButton(title: L("Copiar"), icon: "doc.on.doc", primary: true) { commitText(); ScreenCapture.copy(doc.render()); close() }
                .keyboardShortcut("c", modifiers: .command)
            Button("", action: close).keyboardShortcut(.cancelAction).hidden().frame(width: 0)
        }
    }

    private func drawing(k: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = CGPoint(x: v.location.x / k, y: v.location.y / k)
                let start = CGPoint(x: v.startLocation.x / k, y: v.startLocation.y / k)
                guard tool != .text else { return }
                draft = CaptureMark(kind: tool, a: start, b: p, color: color)
            }
            .onEnded { v in
                let start = CGPoint(x: v.startLocation.x / k, y: v.startLocation.y / k)
                if tool == .text {
                    commitText()
                    typing = CaptureMark(kind: .text, a: start, b: start, color: color)
                    typed = ""
                    DispatchQueue.main.async { textFocus = true }
                    return
                }
                if let d = draft, hypot(d.b.x - d.a.x, d.b.y - d.a.y) > 4 { doc.marks.append(d) }
                draft = nil
            }
    }

    private func commitText() {
        guard var t = typing else { return }
        typing = nil
        let clean = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        t.text = clean
        doc.marks.append(t)
        typed = ""
    }

    private func undo() {
        if typing != nil { typing = nil; typed = ""; return }
        if !doc.marks.isEmpty { doc.marks.removeLast() }
    }

    private func dragProvider() -> NSItemProvider {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(L("Captura") + ".png")
        try? ScreenCapture.png(doc.render())?.write(to: file, options: .atomic)
        return NSItemProvider(contentsOf: file) ?? NSItemProvider()
    }
}

// MARK: Fixada na tela

/// Captura flutuando sobre as outras janelas: arraste para mover, puxe a borda para mudar o tamanho, clique duplo para editar
@MainActor
final class PinnedCapture: NSObject {
    let image: NSImage
    var onClose: (() -> Void)?
    private var panel: NSPanel?

    init(image: NSImage) { self.image = image }

    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let fit = min(1, vf.width * 0.45 / image.size.width, vf.height * 0.45 / image.size.height)
        let size = NSSize(width: image.size.width * fit, height: image.size.height * fit)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentAspectRatio = image.size
        p.contentView = NSHostingView(rootView: PinnedView(image: image,
                                                          onCopy: { [image] in ScreenCapture.copy(image) },
                                                          onEdit: { [weak self] in self?.edit() },
                                                          onClose: { [weak self] in self?.close() }))
        p.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 24, y: vf.maxY - size.height - 24))
        p.orderFrontRegardless()
        panel = p
    }

    private func edit() {
        ScreenCapture.edit(image)
        close()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        onClose?()
    }
}

private struct PinnedView: View {
    let image: NSImage
    var onCopy: () -> Void
    var onEdit: () -> Void
    var onClose: () -> Void
    @State private var hover = false

    var body: some View {
        Image(nsImage: image).resizable().interpolation(.high)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
            .overlay(alignment: .topLeading) {
                if hover {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Circle().fill(.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain).padding(6)
                    .help(L("Fechar"))
                }
            }
            .onHover { hover = $0 }
            .onTapGesture(count: 2, perform: onEdit)
            .contextMenu {
                Button(L("Copiar"), action: onCopy)
                Button(L("Editar"), action: onEdit)
                Divider()
                Button(L("Fechar"), action: onClose)
            }
    }
}
