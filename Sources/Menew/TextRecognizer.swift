import AppKit
import Vision

/// Texto de imagens com o Vision do macOS: roda no Mac, nada sai dele
enum TextRecognizer {
    /// Linhas reconhecidas, de cima para baixo (vazio se não achou texto)
    static func recognize(_ image: CGImage) async -> String {
        await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                cont.resume(returning: "")
            }
        }
    }

    static func recognize(url: URL) async -> String {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return "" }
        return await recognize(image)
    }

    /// Lê a imagem e põe o texto no clipboard (ele entra no histórico como qualquer texto copiado)
    @MainActor
    static func copyText(fromImageAt url: URL) {
        reading()
        Task {
            let text = await Task.detached { await recognize(url: url) }.value
            finish(text)
        }
    }

    /// Você seleciona uma área da tela, como no Print, e o texto dela vai para o clipboard.
    /// A captura fica num arquivo temporário apagado logo em seguida.
    @MainActor
    static func captureScreenText() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("menew-ocr-\(UUID().uuidString).png")
        Task {
            let text: String? = await Task.detached {
                Shell.run("/usr/sbin/screencapture", ["-i", "-x", file.path])
                defer { try? FileManager.default.removeItem(at: file) }
                guard FileManager.default.fileExists(atPath: file.path) else { return nil } // esc: cancelou
                await MainActor.run { reading() }
                return await recognize(url: file)
            }.value
            if let text { finish(text) } else { HUD.hide() }
        }
    }

    /// Aviso imediato: sem ele parece que copiou na hora e o ⌘V cola o conteúdo anterior
    @MainActor
    private static func reading() {
        HUD.show(icon: "text.viewfinder", color: .secondary, text: L("Lendo texto…"), duration: nil)
    }

    @MainActor
    private static func finish(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            HUD.show(icon: "text.viewfinder", color: .orange, text: L("Nenhum texto encontrado"))
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(clean, forType: .string)
        let lines = clean.split(separator: "\n").count
        HUD.show(icon: "text.viewfinder", color: .green,
                 text: lines == 1 ? L("Texto copiado") : L("Texto copiado (%d linhas)", lines))
    }
}
