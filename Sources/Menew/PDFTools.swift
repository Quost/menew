import AppKit
import PDFKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// Juntar, comprimir, girar e converter PDFs da estante, no próprio Mac (PDFKit). Como nas imagens, os originais
/// nunca são alterados: o resultado é um arquivo novo ao lado do primeiro (ou em Downloads) e entra no lugar deles na estante.
enum PDFTool {
    case merge, compress, rotate, toImages, fromImages

    static func isPDF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
    }

    /// `name` vem pronto da thread principal (as traduções vivem nela). Devolve os arquivos novos.
    static func run(_ tool: PDFTool, on urls: [URL], name: String) -> [URL] {
        guard let first = urls.first else { return [] }
        let dir = outputDir(for: first)
        switch tool {
        case .merge:
            let out = PDFDocument()
            for u in urls {
                guard let doc = PDFDocument(url: u) else { continue }
                for i in 0..<doc.pageCount { if let p = doc.page(at: i) { out.insert(p, at: out.pageCount) } }
            }
            let url = unique(dir.appendingPathComponent(name).appendingPathExtension("pdf"))
            return out.pageCount > 0 && out.write(to: url) ? [url] : []

        case .compress:
            return urls.compactMap { u in
                guard let doc = PDFDocument(url: u) else { return nil }
                let url = unique(outputDir(for: u).appendingPathComponent(u.deletingPathExtension().lastPathComponent + name)
                    .appendingPathExtension("pdf"))
                // O filtro "Reduzir Tamanho do Arquivo" do macOS (o mesmo do Preview): recomprime as imagens
                // e mantém o texto selecionável. Se não ficou menor, fica o original.
                guard let filter = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")),
                      doc.write(to: url, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]) else { return nil }
                if size(url) >= size(u) {
                    try? FileManager.default.removeItem(at: url)
                    return u
                }
                return url
            }

        case .rotate:
            return urls.compactMap { u in
                guard let doc = PDFDocument(url: u) else { return nil }
                for i in 0..<doc.pageCount { if let p = doc.page(at: i) { p.rotation = (p.rotation + 90) % 360 } }
                let url = unique(outputDir(for: u).appendingPathComponent(u.deletingPathExtension().lastPathComponent + name)
                    .appendingPathExtension("pdf"))
                return doc.write(to: url) ? url : nil
            }

        case .toImages:
            var out: [URL] = []
            for u in urls {
                guard let doc = PDFDocument(url: u) else { continue }
                let folder = unique(outputDir(for: u).appendingPathComponent(u.deletingPathExtension().lastPathComponent + name))
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for i in 0..<doc.pageCount {
                    guard let page = doc.page(at: i), let png = render(page) else { continue }
                    let file = folder.appendingPathComponent(String(format: "%03d.png", i + 1))
                    if (try? png.write(to: file)) != nil { out.append(file) }
                }
            }
            return out

        case .fromImages:
            let out = PDFDocument()
            for u in urls {
                guard let image = NSImage(contentsOf: u), let page = PDFPage(image: image) else { continue }
                out.insert(page, at: out.pageCount)
            }
            let url = unique(dir.appendingPathComponent(name).appendingPathExtension("pdf"))
            return out.pageCount > 0 && out.write(to: url) ? [url] : []
        }
    }

    private static func size(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// Página em PNG a 2× (boa para ler e mandar em chat)
    private static func render(_ page: PDFPage) -> Data? {
        let box = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let size = NSSize(width: (rotated ? box.height : box.width) * 2, height: (rotated ? box.width : box.height) * 2)
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func outputDir(for url: URL) -> URL {
        FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
            ? url.deletingLastPathComponent()
            : FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// "Juntado.pdf" já existe → "Juntado 2.pdf"
    private static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while true {
            var u = url.deletingLastPathComponent().appendingPathComponent("\(base) \(n)")
            if !ext.isEmpty { u = u.appendingPathExtension(ext) }
            if !fm.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }
}

extension ShelfStore {
    var pdfURLs: [URL] {
        items.compactMap { if case .file(let u) = $0.kind, PDFTool.isPDF(u) { u } else { nil } }
    }

    /// Roda a ferramenta e troca os arquivos usados pelos resultados na estante
    func process(_ tool: PDFTool) {
        let urls = tool == .fromImages ? imageURLs : pdfURLs
        guard !urls.isEmpty else { return }
        let name: String = switch tool {
        case .merge: L("PDFs juntos")
        case .compress: L(" (comprimido)")
        case .rotate: L(" (girado)")
        case .toImages: L(" (páginas)")
        case .fromImages: L("Imagens")
        }
        let before = urls.reduce(Int64(0)) { $0 + Self.size($1) }
        HUD.show(icon: "doc.richtext", color: .secondary, text: L("Processando PDFs…"), duration: nil)
        Task {
            let results = await Task.detached { PDFTool.run(tool, on: urls, name: name) }.value
            guard !results.isEmpty else {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para processar os PDFs"), duration: 2.5)
                return
            }
            replace(urls, with: results)
            switch tool {
            case .compress:
                let after = results.reduce(Int64(0)) { $0 + Self.size($1) }
                HUD.show(icon: "checkmark.circle.fill", color: .green,
                         text: after < before ? L("%@ → %@", Fmt.bytes(before), Fmt.bytes(after)) : L("Já estava compacto"), duration: 2.5)
            case .toImages:
                HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("%d páginas em imagem", results.count))
            default:
                HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("PDF pronto"))
            }
        }
    }

    private static func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

/// Menu "PDF" no topo da estante quando há PDFs nela
struct ShelfPDFMenu: View {
    @ObservedObject var store: ShelfStore

    var body: some View {
        let count = store.pdfURLs.count
        Menu {
            if count > 1 { Button(L("Juntar os %d PDFs", count)) { store.process(.merge) } }
            Button(L("Comprimir")) { store.process(.compress) }
            Button(L("Girar 90°")) { store.process(.rotate) }
            Button(L("Páginas em imagens")) { store.process(.toImages) }
        } label: {
            Image(systemName: "doc.richtext")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .contentShape(Circle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(L("Juntar, comprimir, girar ou converter os PDFs da estante. Os originais ficam intactos."))
    }
}
