import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Converter, reduzir e limpar fotos da estante, no próprio Mac (ImageIO). Os originais nunca são alterados:
/// cada resultado é um arquivo novo ao lado do original (ou em Downloads, se a pasta não aceitar) e entra no lugar dele na estante.
enum ImageTool: Hashable {
    case convert(UTType)
    case resize(Int)
    case stripMetadata

    @MainActor var suffix: String {
        switch self {
        case .convert: ""
        case .resize(let px): " (\(px) px)"
        case .stripMetadata: L(" (sem metadados)")
        }
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    /// Processa uma imagem e devolve o arquivo novo (nil se não deu)
    /// `suffix` vem pronto da thread principal (as traduções vivem nela)
    static func run(_ tool: ImageTool, on url: URL, suffix: String) -> URL? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(src).flatMap({ UTType($0 as String) }) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(w, h)

        var maxPixels = longest
        if case .resize(let px) = tool { maxPixels = min(px, longest) }
        // A miniatura já aplica a rotação da foto; assim o arquivo novo nunca sai deitado
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixels),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }

        var type = sourceType
        if case .convert(let t) = tool { type = t }
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type.identifier)
        if !writable { type = .jpeg }

        // Metadados: mantidos ao converter e reduzir (sem a rotação, já aplicada); nenhum ao limpar
        var meta: [CFString: Any] = [:]
        if tool != .stripMetadata {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary,
                        kCGImagePropertyTIFFDictionary] {
                if var d = props[key] as? [CFString: Any] {
                    d[kCGImagePropertyTIFFOrientation] = nil
                    meta[key] = d
                }
            }
        }
        if type == .jpeg || type == .heic { meta[kCGImageDestinationLossyCompressionQuality] = 0.88 }
        meta[kCGImagePropertyOrientation] = 1

        let ext = type == .jpeg ? "jpg" : (type.preferredFilenameExtension ?? "jpg")
        let base = url.deletingPathExtension().lastPathComponent + suffix
        let dir = FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
            ? url.deletingLastPathComponent()
            : FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let out = unique(dir.appendingPathComponent(base).appendingPathExtension(ext))

        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, meta as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out : nil
    }

    /// "foto.jpg" já existe → "foto 2.jpg"
    private static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while true {
            let u = url.deletingLastPathComponent().appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            if !fm.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }
}

extension ShelfStore {
    var imageURLs: [URL] {
        items.compactMap { if case .file(let u) = $0.kind, ImageTool.isImage(u) { u } else { nil } }
    }

    /// Aplica a ferramenta em todas as imagens da estante e troca cada uma pelo resultado
    func process(_ tool: ImageTool) {
        let urls = imageURLs
        guard !urls.isEmpty else { return }
        HUD.show(icon: "photo.stack", color: .secondary, text: L("Processando imagens…"), duration: nil)
        Task {
            let suffix = tool.suffix
            let results = await Task.detached { urls.map { ($0, ImageTool.run(tool, on: $0, suffix: suffix)) } }.value
            var done = 0
            for (original, out) in results {
                guard let out else { continue }
                done += 1
                replace(original, with: out)
            }
            if done == 0 {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para processar as imagens"), duration: 2.5)
            } else {
                HUD.show(icon: "checkmark.circle.fill", color: .green,
                         text: done == 1 ? L("1 imagem pronta") : L("%d imagens prontas", done))
            }
        }
    }
}

/// Menu "Imagens" no topo da estante quando há fotos nela
struct ShelfImageMenu: View {
    @ObservedObject var store: ShelfStore

    var body: some View {
        Menu {
            Section(L("Converter para")) {
                Button("JPG") { store.process(.convert(.jpeg)) }
                Button("PNG") { store.process(.convert(.png)) }
                Button("HEIC") { store.process(.convert(.heic)) }
            }
            Section(L("Reduzir (lado maior)")) {
                ForEach([3000, 2000, 1200, 800], id: \.self) { px in
                    Button("\(px) px") { store.process(.resize(px)) }
                }
            }
            Divider()
            Button(L("Remover localização e metadados")) { store.process(.stripMetadata) }
            Button(L("Juntar em um PDF")) { store.process(PDFTool.fromImages) }
        } label: {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .contentShape(Circle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(L("Converter, reduzir ou limpar as %d imagens da estante. Os originais ficam intactos.", store.imageURLs.count))
    }
}
