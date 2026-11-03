import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Organizar arquivos pelo conteúdo: o Menew lê cada arquivo de uma pasta (texto de PDFs e documentos, OCR das imagens),
/// a IA do Mac sugere um nome claro e uma pasta, e você revisa antes. Só move e renomeia dentro da mesma pasta,
/// nunca apaga, e dá para desfazer. Sem Apple Intelligence, organiza por tipo.
@MainActor
final class OrganizerModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        var folder: String
        var name: String
        var include = true
        var reason = ""
    }

    struct Move: Codable { let from: String; let to: String }

    @Published var folder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    @Published private(set) var items: [Item] = []
    @Published private(set) var working = false
    @Published private(set) var progress = 0.0
    @Published private(set) var lastMoves: [Move] = []
    @Published private(set) var message: String?

    var folders: [String] { Array(Set(items.map(\.folder))).sorted() }

    // MARK: Ler e sugerir

    func scan() {
        guard !working else { return }
        working = true
        message = nil
        items = []
        progress = 0
        let dir = folder
        Task {
            let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
                                                                       options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true && !Self.skip.contains($0.pathExtension.lowercased()) }
                .prefix(150)
            var out: [Item] = []
            var used: [String] = []
            for (i, url) in files.enumerated() {
                let content = await Task.detached { Self.text(of: url) }.value
                var item = Item(url: url, folder: Self.folderByType(url), name: url.deletingPathExtension().lastPathComponent)
                // Capturas, instaladores e compactados: pela regra; o resto pela IA
                if !Self.byRule(url), let s = await Self.suggest(url: url, content: content, existing: used) {
                    if !s.folder.isEmpty { item.folder = s.folder }
                    if !s.name.isEmpty { item.name = s.name }
                }
                if !used.contains(item.folder) { used.append(item.folder) }
                out.append(item)
                items = out
                progress = Double(i + 1) / Double(max(1, files.count))
            }
            working = false
            if out.isEmpty { message = L("Nenhum arquivo solto nesta pasta.") }
        }
    }

    /// Pastas de apps, pacotes e arquivos em uso ficam de fora
    static let skip: Set<String> = ["app", "download", "crdownload", "part", "localized", "ds_store"]

    /// Até 1500 caracteres do conteúdo: PDF, texto, documentos do Office/Pages pelo AppKit, imagens por OCR
    nonisolated static func text(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        if type?.conforms(to: .pdf) == true, let doc = PDFDocument(url: url) {
            var t = ""
            for i in 0..<min(doc.pageCount, 3) { t += (doc.page(at: i)?.string ?? "") + "\n" }
            if t.trimmingCharacters(in: .whitespacesAndNewlines).count < 20, let page = doc.page(at: 0) {
                let img = page.thumbnail(of: NSSize(width: 1400, height: 1800), for: .mediaBox)
                if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) { t = ocr(cg) }
            }
            return String(t.prefix(1500))
        }
        if type?.conforms(to: .image) == true, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                 kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) {
            return String(ocr(cg).prefix(1500))
        }
        if type?.conforms(to: .text) == true || ["md", "csv", "json", "txt"].contains(ext) {
            return String(((try? String(contentsOf: url, encoding: .utf8)) ?? "").prefix(1500))
        }
        if ["docx", "doc", "rtf", "rtfd", "odt", "html", "webarchive"].contains(ext),
           let s = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            return String(s.string.prefix(1500))
        }
        return ""
    }

    nonisolated private static func ocr(_ cg: CGImage) -> String {
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .accurate
        r.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: cg).perform([r])
        return (r.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Sem IA: a pasta pelo tipo do arquivo
    static func folderByType(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        if name.hasPrefix("screenshot") || name.hasPrefix("captura de tela") || name.hasPrefix("bildschirmfoto") || name.hasPrefix("captura de pantalla") {
            return L("Capturas de tela")
        }
        let t = UTType(filenameExtension: ext)
        if ["dmg", "pkg", "mpkg", "iso"].contains(ext) { return L("Instaladores") }
        if ["zip", "rar", "7z", "tar", "gz", "tgz", "xz"].contains(ext) { return L("Compactados") }
        if t?.conforms(to: .pdf) == true { return "PDFs" }
        if ["xls", "xlsx", "numbers", "csv", "ods"].contains(ext) { return L("Planilhas") }
        if ["ppt", "pptx", "key", "odp"].contains(ext) { return L("Apresentações") }
        if t?.conforms(to: .image) == true { return L("Imagens") }
        if t?.conforms(to: .movie) == true || t?.conforms(to: .audiovisualContent) == true { return L("Vídeos") }
        if t?.conforms(to: .audio) == true { return L("Áudios") }
        if t?.conforms(to: .sourceCode) == true || ["swift", "js", "ts", "py", "json", "yml", "yaml"].contains(ext) { return L("Código") }
        return L("Documentos")
    }

    struct Suggestion { var folder: String; var name: String }

    /// Tipos que a regra já resolve bem
    static func byRule(_ url: URL) -> Bool {
        [L("Capturas de tela"), L("Instaladores"), L("Compactados")].contains(folderByType(url))
    }

    /// As pastas que a IA pode escolher, no idioma do app
    static let kinds: [(key: String, title: () -> String)] = [
        ("invoice", { L("Notas fiscais") }), ("receipt", { L("Recibos") }), ("contract", { L("Contratos") }),
        ("statement", { L("Extratos") }), ("ticket", { L("Passagens e reservas") }), ("id", { L("Documentos pessoais") }),
        ("minutes", { L("Atas e anotações") }), ("report", { L("Relatórios") }), ("presentation", { L("Apresentações") }),
        ("spreadsheet", { L("Planilhas") }), ("photo", { L("Fotos") }), ("design", { L("Design") }), ("code", { L("Código") }),
        ("manual", { L("Manuais") }), ("study", { L("Estudos") }), ("other", { L("Documentos") }),
    ]

    static func suggest(url: URL, content: String, existing: [String]) async -> Suggestion? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), AIText.unavailableReason == nil else { return nil }
        let date = ((try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()).formatted(.iso8601.year().month())
        let language = L10n.current.locale.localizedString(forLanguageCode: L10n.current.rawValue) ?? "English"
        let session = LanguageModelSession(instructions: """
            You organize a person's files. Pick the kind of file from: \(kinds.map(\.key).joined(separator: ", ")). \
            Then write a clear file name without extension: what it is, who or where it is from, and the year-month, \
            like "Invoice - Acme - 2026-10". Write the name in \(language), in normal case (not all caps). \
            Use only facts from the name or content; if there is no content, keep the current name's meaning.
            """)
        let prompt = "Current name: \(url.lastPathComponent)\nDate: \(date)\nContent:\n\(content.isEmpty ? "(none)" : content)"
        guard let r = try? await session.respond(to: prompt, generating: FileSuggestion.self).content else { return nil }
        // Nada de barras ou dois-pontos no nome
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Caixa alta vira normal ("NOTA FISCAL" → "Nota fiscal")
        var name = clean(r.name)
        if name == name.uppercased() && name.count > 6 { name = name.lowercased().prefix(1).uppercased() + name.lowercased().dropFirst() }
        let folder = kinds.first { $0.key == PaletteSearch.fold(r.kind) }?.title() ?? folderByType(url)
        return Suggestion(folder: folder, name: String(name.prefix(90)))
        #else
        return nil
        #endif
    }

    func setFolder(_ id: UUID, _ f: String) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].folder = f } }
    func setName(_ id: UUID, _ n: String) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].name = n } }
    func toggle(_ id: UUID) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].include.toggle() } }

    // MARK: Aplicar e desfazer

    /// Move e renomeia os marcados, dentro da pasta escolhida. Nome repetido ganha " 2".
    func apply() {
        let fm = FileManager.default
        var moves: [Move] = []
        for item in items where item.include {
            let dir = folder.appendingPathComponent(item.folder, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = item.url.pathExtension
            var dest = dir.appendingPathComponent(item.name).appendingPathExtension(ext)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                dest = dir.appendingPathComponent("\(item.name) \(n)").appendingPathExtension(ext)
                n += 1
            }
            if (try? fm.moveItem(at: item.url, to: dest)) != nil { moves.append(Move(from: item.url.path, to: dest.path)) }
        }
        lastMoves = moves
        items = []
        message = L("%d arquivos organizados.", moves.count)
        HUD.show(icon: "folder.fill.badge.gearshape", color: .blue, text: L("%d arquivos organizados", moves.count))
    }

    /// Devolve cada arquivo para onde estava e apaga as pastas que ficaram vazias
    func undo() {
        let fm = FileManager.default
        var dirs: Set<URL> = []
        for m in lastMoves.reversed() {
            let to = URL(fileURLWithPath: m.to)
            dirs.insert(to.deletingLastPathComponent())
            if !fm.fileExists(atPath: m.from) { try? fm.moveItem(at: to, to: URL(fileURLWithPath: m.from)) }
        }
        for d in dirs where ((try? fm.contentsOfDirectory(atPath: d.path)) ?? ["x"]).isEmpty { try? fm.removeItem(at: d) }
        message = L("Tudo voltou para onde estava.")
        lastMoves = []
    }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.directoryURL = folder
        p.prompt = L("Escolher")
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let u = p.url { folder = u; items = []; message = nil }
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct FileSuggestion {
    @Guide(description: "One of the kinds listed in the instructions")
    var kind: String
    @Guide(description: "Clear file name without extension")
    var name: String
}
#endif

import Vision

@MainActor
final class OrganizerWindow {
    static let shared = OrganizerWindow()
    let model = OrganizerModel()
    private var window: NSWindow?

    func show(folder: URL? = nil) {
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        if let folder { model.folder = folder }
        let w = window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = L("Organizar arquivos")
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OrganizerView(model: model))
            w.center()
            return w
        }()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct OrganizerView: View {
    @ObservedObject var model: OrganizerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill").foregroundStyle(.blue)
                Text(model.folder.lastPathComponent).font(.system(size: 14, weight: .semibold))
                Button(L("Outra pasta…")) { model.chooseFolder() }.buttonStyle(.plain).foregroundStyle(Color.accentColor).font(.system(size: 12))
                Spacer()
                if model.working {
                    ProgressView(value: model.progress).frame(width: 140)
                    Text(L("Lendo os arquivos…")).font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    PillButton(title: model.items.isEmpty ? L("Sugerir organização") : L("Sugerir de novo"), icon: "sparkles", primary: model.items.isEmpty) { model.scan() }
                }
            }
            Text(AIText.unavailableReason == nil
                 ? L("A IA do Mac lê cada arquivo e sugere um nome claro e uma pasta. Você revisa antes; nada é apagado, e dá para desfazer.")
                 : L("Sem Apple Intelligence, os arquivos vão para pastas por tipo (PDFs, Imagens, Instaladores…). Você revisa antes."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if model.items.isEmpty {
                VStack(spacing: 10) {
                    if let m = model.message { Text(m).font(.system(size: 13)) }
                    if !model.lastMoves.isEmpty {
                        PillButton(title: L("Desfazer"), icon: "arrow.uturn.backward") { model.undo() }
                        Button(L("Mostrar no Finder")) { NSWorkspace.shared.open(model.folder) }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.items) { item in row(item); Divider() }
                    }
                }
                .card(padding: 0)
                HStack {
                    Text(L("%d de %d arquivos marcados", model.items.filter(\.include).count, model.items.count))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    PillButton(title: L("Organizar"), icon: "folder.badge.gearshape", primary: true) { model.apply() }
                        .disabled(model.working || !model.items.contains(where: \.include))
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 16)
        .frame(minWidth: 680, minHeight: 440)
        .background(Theme.windowFill)
    }

    private func row(_ item: OrganizerModel.Item) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { item.include }, set: { _ in model.toggle(item.id) })).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                    TextField("", text: Binding(get: { item.name }, set: { model.setName(item.id, $0) }))
                        .textFieldStyle(.plain).font(.system(size: 12.5, weight: .medium))
                    Text("." + item.url.pathExtension).font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(model.folders, id: \.self) { f in Button(f) { model.setFolder(item.id, f) } }
            } label: {
                Label(item.folder, systemImage: "folder").font(.system(size: 12)).lineLimit(1)
            }
            .menuStyle(.button).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .opacity(item.include ? 1 : 0.5)
    }
}
