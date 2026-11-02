import AppKit
import CoreImage
import SwiftUI
import Vision
import VisionKit

/// Imagem com Live Text: dá para selecionar o texto, clicar em links, telefones e endereços, como no app Fotos.
/// A análise roda no Mac (VisionKit) quando a imagem aparece; sem suporte, mostra só a imagem.
struct LiveTextImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> LiveTextView { LiveTextView(image: image) }
    func updateNSView(_ view: LiveTextView, context: Context) { view.set(image) }
}

final class LiveTextView: NSView {
    private let imageView = NSImageView()
    private let overlay = ImageAnalysisOverlayView()
    private var task: Task<Void, Never>?
    private var current: NSImage?

    init(image: NSImage) {
        super.init(frame: .zero)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.trackingImageView = imageView
        addSubview(overlay)
        set(image)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ image: NSImage) {
        guard image !== current else { return }
        current = image
        imageView.image = image
        overlay.analysis = nil
        task?.cancel()
        guard ImageAnalyzer.isSupported else { return }
        task = Task { @MainActor [weak self] in
            let config = ImageAnalyzer.Configuration([.text, .machineReadableCode])
            guard let analysis = try? await ImageAnalyzer().analyze(image, orientation: .up, configuration: config),
                  !Task.isCancelled, let self else { return }
            self.overlay.analysis = analysis
            // O botão do Live Text no canto e a seleção direta do texto
            self.overlay.preferredInteractionTypes = .automatic
        }
    }
}

// MARK: Remover fundo

/// Recorta o assunto principal da foto (pessoa, animal, objeto) com o Vision, no Mac. Devolve PNG com fundo transparente.
enum BackgroundRemover {
    static func cutout(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil, let result = request.results?.first,
              let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// O assunto da imagem copiada vai para o clipboard, sem o fundo
    @MainActor static func fromClipboard() {
        guard let img = NSImage(pasteboard: .general), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            HUD.show(icon: "photo", color: .orange, text: L("Copie uma imagem primeiro"), duration: 2)
            return
        }
        HUD.show(icon: "wand.and.stars", color: .secondary, text: L("Removendo o fundo…"), duration: nil)
        Task {
            let data = await Task.detached { cutout(cg).flatMap(png) }.value
            guard let data else {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não achei um assunto na imagem"), duration: 2.5)
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(data, forType: .png)
            HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Copiado sem o fundo"))
        }
    }
}
