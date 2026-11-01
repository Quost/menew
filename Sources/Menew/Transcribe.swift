import AppKit
import AVFoundation
import Speech
import SwiftUI
import UniformTypeIdentifiers

/// Transcrever áudio e vídeo da estante sem internet: o texto vira uma nota no Menew e vai para o clipboard.
/// macOS 26: o transcritor novo da Apple (sem pedir permissão, ótimo com falas longas). Antes disso: o reconhecimento
/// de fala clássico, no aparelho, que pede permissão na primeira vez.
enum Transcriber {
    static let languages: [(code: String, name: String)] = [
        ("pt-BR", "Português"), ("en-US", "English"), ("es-ES", "Español"), ("de-DE", "Deutsch"), ("zh-CN", "中文"),
        ("fr-FR", "Français"), ("it-IT", "Italiano"), ("ja-JP", "日本語"),
    ]

    static func isMedia(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension) else { return false }
        return t.conforms(to: .audio) || t.conforms(to: .movie) || t.conforms(to: .audiovisualContent)
    }

    /// Idioma do Menew primeiro
    @MainActor static var preferred: [(code: String, name: String)] {
        let current = L10n.current == .pt ? "pt-BR" : L10n.current == .de ? "de-DE" : L10n.current == .es ? "es-ES"
            : L10n.current == .zh ? "zh-CN" : "en-US"
        return languages.sorted { a, _ in a.code == current }
    }

    static func transcribe(_ url: URL, locale code: String) async throws -> String {
        let audio = try await audioFile(for: url)
        defer { if audio != url { try? FileManager.default.removeItem(at: audio) } }
        if #available(macOS 26, *) {
            return try await modern(audio, locale: Locale(identifier: code))
        }
        return try await classic(audio, locale: Locale(identifier: code))
    }

    /// Vídeo (e formatos que o leitor de áudio não abre) vira um .m4a temporário só com o som
    private static func audioFile(for url: URL) async throws -> URL {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true, (try? AVAudioFile(forReading: url)) != nil { return url }
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw CocoaError(.fileReadCorruptFile) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("menew-audio-\(UUID().uuidString).m4a")
        try await export.export(to: out, as: .m4a)
        return out
    }

    @available(macOS 26, *)
    private static func modern(_ url: URL, locale: Locale) async throws -> String {
        let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let transcriber = SpeechTranscriber(locale: loc, preset: .transcription)
        // O modelo do idioma é baixado pelo macOS na primeira vez (e depois fica no Mac)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        async let text: String = {
            var parts: [String] = []
            for try await r in transcriber.results { parts.append(String(r.text.characters).trimmingCharacters(in: .whitespaces)) }
            return parts.filter { !$0.isEmpty }.joined(separator: " ")
        }()
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await text
    }

    private static func classic(_ url: URL, locale: Locale) async throws -> String {
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized, let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw CocoaError(.userCancelled)
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { c in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let error { done = true; c.resume(throwing: error); return }
                if let result, result.isFinal { done = true; c.resume(returning: result.bestTranscription.formattedString) }
            }
        }
    }
}

extension ShelfStore {
    var mediaURLs: [URL] {
        items.compactMap { if case .file(let u) = $0.kind, Transcriber.isMedia(u) { u } else { nil } }
    }

    /// Transcreve cada áudio/vídeo da estante, cria uma nota com o texto e copia
    func transcribe(locale: String) {
        let urls = mediaURLs
        guard !urls.isEmpty else { return }
        HUD.show(icon: "waveform", color: .secondary, text: L("Transcrevendo…"), duration: nil)
        Task {
            var texts: [String] = []
            for url in urls {
                do {
                    let text = try await Task.detached { try await Transcriber.transcribe(url, locale: locale) }.value
                    guard !text.isEmpty else { continue }
                    let title = L("Transcrição: %@", url.deletingPathExtension().lastPathComponent)
                    _ = (NSApp.delegate as? AppDelegate)?.notes.create(text: title + "\n\n" + text)
                    texts.append(text)
                } catch {
                    continue
                }
            }
            guard !texts.isEmpty else {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para transcrever"), duration: 2.5)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(texts.joined(separator: "\n\n"), forType: .string)
            HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Transcrição copiada e salva nas Notas"), duration: 2)
        }
    }
}

/// Menu "Transcrever" no topo da estante quando há áudio ou vídeo nela
struct ShelfMediaMenu: View {
    @ObservedObject var store: ShelfStore

    var body: some View {
        Menu {
            Section(L("Transcrever em")) {
                ForEach(Transcriber.preferred, id: \.code) { lang in
                    Button(lang.name) { store.transcribe(locale: lang.code) }
                }
            }
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .contentShape(Circle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(L("Transcrever os áudios e vídeos da estante, sem internet. O texto vira uma nota."))
    }
}
