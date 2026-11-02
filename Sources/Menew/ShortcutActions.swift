import AppIntents
import AppKit
import ImageIO
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers
#if canImport(Translation)
import Translation
#endif

// Ações do Menew que devolvem um resultado no app Atalhos: dá para encadear com outras ações
// ("pegar o último item copiado → traduzir → criar nota"). Tudo roda no Mac, sem internet.

@MainActor
private var app: AppDelegate? { NSApp.delegate as? AppDelegate }

/// Erros que o Atalhos mostra para a pessoa
enum MenewIntentError: Error, CustomLocalizedStringResourceConvertible {
    case needsAI(String)
    case needsMacOS26
    case noText
    case unreadable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .needsAI(let reason): "\(reason)"
        case .needsMacOS26: "This action needs macOS 26 or later."
        case .noText: "There is no text to work with."
        case .unreadable: "Menew couldn't read this file."
        }
    }
}

// MARK: Sistema

enum SystemMetric: String, AppEnum {
    case cpu, memory, diskFree, battery, uptime

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "System Metric"
    static let caseDisplayRepresentations: [SystemMetric: DisplayRepresentation] = [
        .cpu: "CPU Usage (%)",
        .memory: "Memory Used (%)",
        .diskFree: "Free Disk Space (GB)",
        .battery: "Battery Level (%)",
        .uptime: "Uptime (hours)",
    ]
}

struct GetSystemMetricIntent: AppIntent {
    static let title: LocalizedStringResource = "Get System Metric"
    static let description = IntentDescription("Returns CPU, memory, free disk space, battery level or uptime as a number, to use in other actions.")

    @Parameter(title: "Metric", default: .cpu) var metric: SystemMetric

    static var parameterSummary: some ParameterSummary { Summary("Get \(\.$metric)") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        guard let m = app?.monitor else { return .result(value: 0) }
        let v: Double = switch metric {
        case .cpu: (m.cpu * 100).rounded()
        case .memory: m.memTotal == 0 ? 0 : (Double(m.memUsed) / Double(m.memTotal) * 100).rounded()
        case .diskFree: (Double(m.diskFree) / 1_000_000_000 * 10).rounded() / 10
        case .battery: Double(m.battery?.percent ?? 0)
        case .uptime: (ProcessInfo.processInfo.systemUptime / 3600 * 10).rounded() / 10
        }
        return .result(value: v)
    }
}

// MARK: Clipboard

struct GetClipboardHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Clipboard History"
    static let description = IntentDescription("Returns the latest texts you copied, newest first. Items copied from password managers are never saved.")

    @Parameter(title: "Count", default: 5, inclusiveRange: (1, 50)) var count: Int
    @Parameter(title: "Containing") var query: String?

    static var parameterSummary: some ParameterSummary { Summary("Get the last \(\.$count) copied texts containing \(\.$query)") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        guard let clip = app?.clipboard else { return .result(value: []) }
        let q = PaletteSearch.fold(query ?? "")
        let texts = clip.items.filter { $0.kind == .text }.compactMap(\.text).filter { q.isEmpty || PaletteSearch.fold($0).contains(q) }
        return .result(value: Array(texts.prefix(max(1, count))))
    }
}

// MARK: Notas

struct FindNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Notes"
    static let description = IntentDescription("Returns the text of your Menew notes, optionally only the ones containing a word. Protected notes are left out.")

    @Parameter(title: "Containing") var query: String?

    static var parameterSummary: some ParameterSummary { Summary("Find notes containing \(\.$query)") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        guard let notes = app?.notes else { return .result(value: []) }
        let q = PaletteSearch.fold(query ?? "")
        let list = notes.notes.filter { !$0.secure && !$0.isPasswords && (q.isEmpty || PaletteSearch.fold($0.text).contains(q)) }.map(\.text)
        return .result(value: list)
    }
}

struct AppendToNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Note"
    static let description = IntentDescription("Adds a line to the end of a note, found by its title. Creates the note if it doesn't exist.")

    @Parameter(title: "Note Title") var noteTitle: String
    @Parameter(title: "Text") var text: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$text) to note \(\.$noteTitle)") }

    @MainActor func perform() async throws -> some IntentResult {
        guard let notes = app?.notes else { return .result() }
        let wanted = PaletteSearch.fold(noteTitle.trimmingCharacters(in: .whitespaces))
        // Protegidas e de senhas ficam de fora: precisam do Touch ID
        if let n = notes.notes.first(where: { !$0.secure && !$0.isPasswords && PaletteSearch.fold($0.title) == wanted }) {
            notes.setText(n.text.trimmingCharacters(in: .newlines) + "\n" + text, of: n.id)
        } else {
            _ = notes.create(text: "# \(noteTitle)\n\n\(text)")
        }
        return .result()
    }
}

// MARK: Texto

enum TextStyle: String, AppEnum {
    case summarize, fix, clearer, formal, friendly, shorter

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Text Style"
    static let caseDisplayRepresentations: [TextStyle: DisplayRepresentation] = [
        .summarize: "Summarize",
        .fix: "Fix Spelling and Grammar",
        .clearer: "Make Clearer",
        .formal: "Make More Formal",
        .friendly: "Make Friendlier",
        .shorter: "Make Shorter",
    ]

    var action: AIAction {
        switch self {
        case .summarize: .summarize
        case .fix: .fix
        case .clearer: .clearer
        case .formal: .formal
        case .friendly: .friendly
        case .shorter: .shorter
        }
    }
}

struct RewriteTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Rewrite Text with AI"
    static let description = IntentDescription("Summarizes, fixes or rewrites text with Apple's on-device model. Nothing leaves your Mac. Needs Apple Intelligence.")

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Style", default: .summarize) var style: TextStyle

    static var parameterSummary: some ParameterSummary { Summary("\(\.$style) \(\.$text)") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        if let reason = AIText.unavailableReason { throw MenewIntentError.needsAI(reason) }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw MenewIntentError.noText }
        return .result(value: try await AIText.generate(style.action, t))
    }
}

enum TranslateTarget: String, AppEnum {
    case en, pt, es, de, fr, it, ja, zh

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Language"
    static let caseDisplayRepresentations: [TranslateTarget: DisplayRepresentation] = [
        .en: "English", .pt: "Portuguese", .es: "Spanish", .de: "German",
        .fr: "French", .it: "Italian", .ja: "Japanese", .zh: "Chinese",
    ]
}

struct TranslateTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Text"
    static let description = IntentDescription("Translates text with Apple's translator on your Mac, without the internet once the language is downloaded. Doesn't need Apple Intelligence.")

    @Parameter(title: "Text") var text: String
    @Parameter(title: "To", default: .en) var target: TranslateTarget

    static var parameterSummary: some ParameterSummary { Summary("Translate \(\.$text) to \(\.$target)") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw MenewIntentError.noText }
        #if canImport(Translation)
        if #available(macOS 26, *) {
            let session = TranslationSession(installedSource: Locale.Language(identifier: NLLanguageRecognizer.dominantLanguage(for: t)?.rawValue ?? "en"),
                                             target: Locale.Language(identifier: target.rawValue))
            return .result(value: try await session.translate(t).targetText)
        }
        #endif
        throw MenewIntentError.needsMacOS26
    }
}

enum TextTransformKind: String, AppEnum {
    case upper, lower, title, sentence, noAccents, trim, sortLines, uniqueLines, jsonPretty, jsonMinify,
         base64Encode, base64Decode, urlEncode, urlDecode, camel, snake, kebab

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Text Transformation"
    static let caseDisplayRepresentations: [TextTransformKind: DisplayRepresentation] = [
        .upper: "UPPERCASE", .lower: "lowercase", .title: "Title Case", .sentence: "Sentence case",
        .noAccents: "Remove Accents", .trim: "Remove Extra Spaces", .sortLines: "Sort Lines", .uniqueLines: "Remove Duplicate Lines",
        .jsonPretty: "Format JSON", .jsonMinify: "Minify JSON", .base64Encode: "Base64 Encode", .base64Decode: "Base64 Decode",
        .urlEncode: "URL Encode", .urlDecode: "URL Decode", .camel: "camelCase", .snake: "snake_case", .kebab: "kebab-case",
    ]
}

struct TransformTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Transform Text"
    static let description = IntentDescription("Changes case, removes accents, sorts lines, formats JSON, encodes Base64 or URLs and more.")

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Transformation", default: .upper) var kind: TextTransformKind

    static var parameterSummary: some ParameterSummary { Summary("\(\.$kind) \(\.$text)") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let t = TextTransform(rawValue: kind.rawValue), let out = t.apply(text) else { throw MenewIntentError.noText }
        return .result(value: out)
    }
}

// MARK: Imagens

struct RecognizeTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Text from Image"
    static let description = IntentDescription("Recognizes the text in an image or PDF page on your Mac (Vision) and returns it.")

    @Parameter(title: "Image") var file: IntentFile

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let image = NSImage(data: file.data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw MenewIntentError.unreadable }
        return .result(value: await TextRecognizer.recognize(image))
    }
}

struct MakeQRCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Make QR Code"
    static let description = IntentDescription("Turns text or a link into a QR code image.")

    @Parameter(title: "Text") var text: String

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let img = QRCode.image(for: text), let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { throw MenewIntentError.noText }
        return .result(value: IntentFile(data: png, filename: "QR.png", type: .png))
    }
}

enum ImageFormat: String, AppEnum {
    case jpeg, png, heic

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Image Format"
    static let caseDisplayRepresentations: [ImageFormat: DisplayRepresentation] = [.jpeg: "JPEG", .png: "PNG", .heic: "HEIC"]
    var type: UTType { switch self { case .jpeg: .jpeg; case .png: .png; case .heic: .heic } }
}

struct ConvertImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Convert Image"
    static let description = IntentDescription("Converts an image to JPEG, PNG or HEIC, optionally resizing it and removing location and camera data.")

    @Parameter(title: "Image") var file: IntentFile
    @Parameter(title: "Format", default: .jpeg) var format: ImageFormat
    @Parameter(title: "Max Size (px)") var maxSize: Int?
    @Parameter(title: "Remove Location and Metadata", default: true) var strip: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$file) to \(\.$format)") {
            \.$maxSize
            \.$strip
        }
    }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let out = Self.convert(file.data, to: format.type, maxPixels: maxSize, strip: strip) else { throw MenewIntentError.unreadable }
        let base = (file.filename as NSString).deletingPathExtension
        return .result(value: IntentFile(data: out, filename: "\(base.isEmpty ? "Image" : base).\(format.type.preferredFilenameExtension ?? "img")", type: format.type))
    }

    /// Mesma receita da estante: a miniatura já aplica a rotação; sem `strip`, mantém EXIF e GPS
    nonisolated static func convert(_ data: Data, to type: UTType, maxPixels: Int?, strip: Bool) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let longest = max(props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(maxPixels ?? longest, longest)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        var meta: [CFString: Any] = [:]
        if !strip {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary] {
                if var d = props[key] as? [CFString: Any] { d[kCGImagePropertyTIFFOrientation] = nil; meta[key] = d }
            }
        }
        if type != .png { meta[kCGImageDestinationLossyCompressionQuality] = 0.88 }
        meta[kCGImagePropertyOrientation] = 1
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, meta as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

// MARK: Agenda e timers

struct GetNextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Next Meeting"
    static let description = IntentDescription("Returns the title and start time of your next meeting today, from the Calendar app. Turn on the calendar in Menew first.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let m = MeetingStore.shared.next else { return .result(value: "") }
        return .result(value: "\(m.title) — \(m.start.formatted(date: .omitted, time: .shortened))")
    }
}

struct JoinNextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Join Next Meeting"
    static let description = IntentDescription("Opens the link of your next meeting (Zoom, Meet, Teams…).")

    @MainActor func perform() async throws -> some IntentResult {
        MeetingStore.shared.join()
        return .result()
    }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    static let description = IntentDescription("Starts a timer that shows in the menu bar and the notch, with a sound and a notification at the end.")

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (1, 1440)) var minutes: Int
    @Parameter(title: "Label") var label: String?

    static var parameterSummary: some ParameterSummary { Summary("Start a \(\.$minutes) minute timer named \(\.$label)") }

    @MainActor func perform() async throws -> some IntentResult {
        TimerStore.shared.add(label: label ?? "", end: Date().addingTimeInterval(Double(minutes) * 60), isAlarm: false)
        return .result()
    }
}

struct GetScreenTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Screen Time Today"
    static let description = IntentDescription("Returns how many minutes you used your Mac today, in total or only in apps marked as distraction. Turn on screen time in Menew first.")

    @Parameter(title: "Only Distractions", default: false) var distractions: Bool

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let st = ScreenTime.shared
        let today = [ScreenTime.dayKey(Date())]
        let seconds = distractions ? st.byCategory(today)[.distraction] ?? 0 : st.totals(today).reduce(0) { $0 + $1.seconds }
        return .result(value: (seconds / 60).rounded())
    }
}

struct RemoveBackgroundIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Background"
    static let description = IntentDescription("Keeps only the subject of a photo (a person, pet or object) with a transparent background, as a PNG. Runs on your Mac.")

    @Parameter(title: "Image") var file: IntentFile

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let data = file.data
        let out = await Task.detached { () -> Data? in
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  // A miniatura no tamanho cheio já vem na rotação certa
                  let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                                                         kCGImageSourceThumbnailMaxPixelSize: 8192] as CFDictionary) else { return nil }
            return BackgroundRemover.cutout(img).flatMap(BackgroundRemover.png)
        }.value
        guard let out else { throw MenewIntentError.unreadable }
        let base = (file.filename as NSString).deletingPathExtension
        return .result(value: IntentFile(data: out, filename: "\(base.isEmpty ? "Image" : base).png", type: .png))
    }
}

// MARK: PDF

struct ExtractPDFTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Text from PDF"
    static let description = IntentDescription("Returns all the text in a PDF. Scanned pages without text are read on your Mac (Vision).")

    @Parameter(title: "PDF") var file: IntentFile

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let data = file.data
        let text = await Task.detached { PDFDocument(data: data).map(PDFTool.text(of:)) }.value
        guard let text else { throw MenewIntentError.unreadable }
        return .result(value: text)
    }
}

struct ProtectPDFIntent: AppIntent {
    static let title: LocalizedStringResource = "Protect PDF with Password"
    static let description = IntentDescription("Returns a copy of the PDF that asks for a password to open.")

    @Parameter(title: "PDF") var file: IntentFile
    @Parameter(title: "Password") var password: String

    static var parameterSummary: some ParameterSummary { Summary("Protect \(\.$file) with \(\.$password)") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard !password.isEmpty, let doc = PDFDocument(data: file.data),
              let out = doc.dataRepresentation(options: [PDFDocumentWriteOption.userPasswordOption: password, PDFDocumentWriteOption.ownerPasswordOption: password])
        else { throw MenewIntentError.unreadable }
        return .result(value: IntentFile(data: out, filename: file.filename.isEmpty ? "Protected.pdf" : file.filename, type: .pdf))
    }
}
