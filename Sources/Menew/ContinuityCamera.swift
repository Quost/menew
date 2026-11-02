import AppKit
import PDFKit

/// Câmera de Continuidade: tire uma foto, escaneie um documento ou desenhe no iPhone/iPad e o resultado cai no Menew,
/// no clipboard, na estante ou só o texto. Usa o menu "Importar do iPhone" do próprio macOS (mesma conta iCloud, Wi-Fi e
/// Bluetooth ligados); a foto vem direto pelo sistema, sem passar pela internet do Menew.
@MainActor
final class ContinuityCamera: NSObject {
    static let shared = ContinuityCamera()

    enum Destination { case clipboard, shelf, text }

    private var panel: NSPanel?
    private var destination: Destination = .clipboard

    /// Abre, perto do mouse, o menu do sistema com os aparelhos por perto (Tirar foto, Escanear documentos, Adicionar desenho)
    func showMenu(_ destination: Destination) {
        self.destination = destination
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        let mouse = NSEvent.mouseLocation
        // O menu precisa de uma janela ativa com quem receber a imagem: uma janelinha invisível sob o mouse
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 2, height: 2), styleMask: [.borderless], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .popUpMenu
            p.contentView = ImportReceiver { [weak self] pb in self?.receive(pb) ?? false }
            return p
        }()
        panel = p
        p.setFrameOrigin(NSPoint(x: mouse.x, y: mouse.y))
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(p.contentView)

        let menu = NSMenu()
        let title = NSMenuItem(title: Self.title(destination), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let item = NSMenuItem(title: L("Importar do iPhone ou iPad"), action: nil, keyEquivalent: "")
        item.identifier = NSMenuItem.importFromDeviceIdentifier
        menu.addItem(item)
        menu.popUp(positioning: nil, at: .zero, in: p.contentView)
        // A foto chega depois, por readSelection: a janelinha (invisível) espera até 3 minutos
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak p] in p?.orderOut(nil) }
    }

    static func title(_ d: Destination) -> String {
        switch d {
        case .clipboard: L("Do iPhone para o clipboard")
        case .shelf: L("Do iPhone para a estante")
        case .text: L("Do iPhone, só o texto")
        }
    }

    /// O que chegou do aparelho: um PDF (documento escaneado) ou uma imagem (foto, desenho)
    @discardableResult
    func receive(_ pb: NSPasteboard) -> Bool {
        let pdf = pb.data(forType: .pdf)
        let image = pdf == nil ? NSImage(pasteboard: pb) : nil
        guard pdf != nil || image != nil else { return false }
        panel?.orderOut(nil)
        switch destination {
        case .clipboard:
            let out = NSPasteboard.general
            out.clearContents()
            if let pdf { out.setData(pdf, forType: .pdf) } else if let image { out.writeObjects([image]) }
            HUD.show(icon: "iphone", color: .green, text: pdf != nil ? L("Documento copiado") : L("Foto copiada"))
        case .shelf:
            guard let url = Self.save(pdf: pdf, image: image) else { return false }
            ShelfStore.shared.add([ShelfItem(kind: .file(url))])
            (NSApp.delegate as? AppDelegate)?.shelf.show(nearMouse: false)
            HUD.show(icon: "iphone", color: .green, text: L("Na estante e em Downloads"))
        case .text:
            HUD.show(icon: "text.viewfinder", color: .secondary, text: L("Lendo o texto…"), duration: nil)
            let pages = Self.images(pdf: pdf, image: image)
            Task {
                var parts: [String] = []
                for p in pages { parts.append(await TextRecognizer.recognize(p)) }
                let text = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
                guard !text.isEmpty else {
                    HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Nenhum texto encontrado"), duration: 2.5)
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Texto copiado"))
            }
        }
        return true
    }

    /// Guarda em Downloads com data e hora no nome ("iPhone 2026-11-02 16.05.31.jpg")
    static func save(pdf: Data?, image: NSImage?) -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let base = "iPhone \(f.string(from: Date()))"
        if let pdf {
            let url = dir.appendingPathComponent(base + ".pdf")
            return (try? pdf.write(to: url)) != nil ? url : nil
        }
        guard let tiff = image?.tiffRepresentation, let jpg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else { return nil }
        let url = dir.appendingPathComponent(base + ".jpg")
        return (try? jpg.write(to: url)) != nil ? url : nil
    }

    /// Cada página do PDF (ou a foto) como imagem, para ler o texto
    static func images(pdf: Data?, image: NSImage?) -> [CGImage] {
        if let pdf, let doc = PDFDocument(data: pdf) {
            return (0..<doc.pageCount).compactMap { i in
                guard let page = doc.page(at: i) else { return nil }
                let box = page.bounds(for: .mediaBox)
                let scale = 2000 / max(box.width, box.height)
                return page.thumbnail(of: NSSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
                    .cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
        }
        return image?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { [$0] } ?? []
    }
}

/// Quem recebe a imagem do iPhone: o macOS só oferece "Importar do iPhone" para quem aceita imagens
final class ImportReceiver: NSView, NSServicesMenuRequestor {
    private let onReceive: (NSPasteboard) -> Bool

    init(onReceive: @escaping (NSPasteboard) -> Bool) {
        self.onReceive = onReceive
        super.init(frame: NSRect(x: 0, y: 0, width: 2, height: 2))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if let returnType, sendType == nil, NSImage.imageTypes.contains(returnType.rawValue) || returnType == .pdf { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func readSelection(from pboard: NSPasteboard) -> Bool {
        MainActor.assumeIsolated { onReceive(pboard) }
    }

    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { false }
}
