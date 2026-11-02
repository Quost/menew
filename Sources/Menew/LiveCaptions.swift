import AppKit
import AVFoundation
import NaturalLanguage
import ScreenCaptureKit
import Speech
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Legendas ao vivo: o som do Mac (uma chamada, um vídeo) ou o microfone vira texto numa janelinha flutuante e,
/// no macOS 26, também a tradução. O reconhecimento e a tradução rodam no Mac; nada é gravado nem enviado.
@MainActor
final class LiveCaptions: NSObject, ObservableObject {
    static let shared = LiveCaptions()

    enum Source: String { case system, mic }

    @Published private(set) var original = ""
    @Published private(set) var translated = ""
    @Published private(set) var running = false
    @Published private(set) var status: String?
    @Published var source: Source = Source(rawValue: UserDefaults.standard.string(forKey: "captions.source") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "captions.source"); if running { restart() } }
    }
    /// Idioma falado (código do reconhecimento, ex. "en-US") e idioma da tradução ("" = sem tradução)
    @Published var from = UserDefaults.standard.string(forKey: "captions.from") ?? "en-US" {
        didSet { UserDefaults.standard.set(from, forKey: "captions.from"); if running { restart() } }
    }
    @Published var to = UserDefaults.standard.string(forKey: "captions.to") ?? LiveCaptions.defaultTarget {
        didSet { UserDefaults.standard.set(to, forKey: "captions.to"); translated = ""; scheduleTranslation() }
    }

    static var defaultTarget: String { L10n.current == .zh ? "zh" : L10n.current.rawValue }
    static var canTranslate: Bool { if #available(macOS 26, *) { true } else { false } }

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var stream: SCStream?
    private let output = CaptionAudioOutput()
    private var engine: AVAudioEngine?
    private var segmentStart = Date()
    private var translateWork: DispatchWorkItem?
    private var lastTranslated = ""
    private var panel: NSPanel?
    /// ModernCaptionEngine no macOS 26 (guardado como Any para compilar no 14)
    private var modern: AnyObject?

    /// Para as capturas de tela
    func showDemo(original: String, translated: String) {
        running = true
        self.original = original
        self.translated = translated
        status = nil
    }

    // MARK: Ligar e desligar

    func toggle() { running ? stop() : start() }

    func start() {
        showPanel()
        status = L("Preparando…")
        if #available(macOS 26, *) {
            Task { await begin() }
            return
        }
        SFSpeechRecognizer.requestAuthorization { auth in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard auth == .authorized else {
                        LiveCaptions.shared.status = L("Permita o reconhecimento de fala em Ajustes do Sistema › Privacidade.")
                        return
                    }
                    Task { await LiveCaptions.shared.begin() }
                }
            }
        }
    }

    private func begin() async {
        original = ""
        translated = ""
        if #available(macOS 26, *) {
            // O transcritor novo da Apple: no Mac, sem pedir permissão, ótimo com fala contínua
            do {
                let engine = ModernCaptionEngine { text in
                    Task { @MainActor in LiveCaptions.shared.show(text) }
                }
                try await engine.start(locale: Locale(identifier: from))
                modern = engine
                output.feed = { [weak engine] in engine?.feed($0) }
            } catch {
                status = L("Este idioma não está disponível para legendas.")
                return
            }
        } else {
            guard let r = SFSpeechRecognizer(locale: Locale(identifier: from)), r.isAvailable else {
                status = L("Este idioma não está disponível para legendas.")
                return
            }
            recognizer = r
            newRequest()
        }
        running = true
        do {
            if source == .system { try await startSystemAudio() } else { try startMic() }
            status = nil
        } catch {
            status = source == .system ? L("Permita a gravação de tela e áudio do sistema para o Menew em Ajustes do Sistema › Privacidade.")
                                       : L("Não deu para usar o microfone.")
            stop(keepPanel: true)
        }
    }

    func stop(keepPanel: Bool = false) {
        running = false
        output.feed = nil
        if #available(macOS 26, *) { (modern as? ModernCaptionEngine)?.stop() }
        modern = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        output.request = nil
        if let s = stream { Task { try? await s.stopCapture() } }
        stream = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        if !keepPanel { panel?.orderOut(nil) }
    }

    private func restart() {
        stop(keepPanel: true)
        start()
    }

    /// Um pedido novo a cada frase longa: o texto na tela fica curto e o reconhecimento não acumula
    private func newRequest() {
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
        req.addsPunctuation = true
        request = req
        output.request = req
        segmentStart = Date()
        task = recognizer?.recognitionTask(with: req) { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? (error != nil)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { LiveCaptions.shared.update(text: text, final: final, from: req) }
            }
        }
    }

    private func update(text: String?, final: Bool, from req: SFSpeechAudioBufferRecognitionRequest) {
        guard running, req === request else { return }
        if let text, !text.isEmpty {
            original = Self.tail(text)
            scheduleTranslation()
        }
        // Frase terminou (ou passou de 40 s): começa outra, mantendo o último texto na tela
        if final || Date().timeIntervalSince(segmentStart) > 40 {
            req.endAudio()
            newRequest()
        }
    }

    private func show(_ text: String) {
        guard running, !text.isEmpty else { return }
        original = Self.tail(text)
        scheduleTranslation()
    }

    /// As últimas ~2 linhas, cortando numa palavra
    nonisolated static func tail(_ s: String, max: Int = 160) -> String {
        guard s.count > max else { return s }
        let cut = s.suffix(max)
        return "…" + (cut.firstIndex(of: " ").map { String(cut[cut.index(after: $0)...]) } ?? String(cut))
    }

    // MARK: Áudio

    private func startSystemAudio() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CocoaError(.featureUnsupported) }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16_000
        config.channelCount = 1
        // Só o som interessa: vídeo mínimo, uma imagem por segundo
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let s = SCStream(filter: filter, configuration: config, delegate: nil)
        try s.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        try await s.startCapture()
        stream = s
    }

    private func startMic() throws {
        let e = AVAudioEngine()
        let input = e.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [output] buffer, _ in
            output.request?.append(buffer)
            output.feed?(buffer)
        }
        try e.start()
        engine = e
    }

    // MARK: Tradução

    private func scheduleTranslation() {
        translateWork?.cancel()
        guard Self.canTranslate, !to.isEmpty, !original.isEmpty else { return }
        let w = DispatchWorkItem { Task { await LiveCaptions.shared.translate() } }
        translateWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    private func translate() async {
        let text = original
        guard text != lastTranslated else { return }
        let source = String(from.prefix(2))
        guard source != to else { translated = ""; return }
        #if canImport(Translation)
        if #available(macOS 26, *) {
            do {
                let session = TranslationSession(installedSource: Locale.Language(identifier: source), target: Locale.Language(identifier: to))
                let r = try await session.translate(text)
                guard text == original else { return }
                translated = r.targetText
                lastTranslated = text
            } catch {
                status = L("Baixe os idiomas em Ajustes do Sistema › Geral › Idioma e Região › Idiomas de Tradução.")
            }
        }
        #endif
    }

    // MARK: Janela

    private func showPanel() {
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 150),
                            styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: CaptionsView(model: self))
            if let vf = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: vf.midX - 360, y: vf.minY + 60)) }
            return p
        }()
        panel = p
        p.orderFrontRegardless()
    }
}

/// Recebe o áudio do ScreenCaptureKit e passa direto para o reconhecimento
final class CaptionAudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "menew.captions.audio")
    var request: SFSpeechAudioBufferRecognitionRequest?
    /// Motor novo (macOS 26): recebe o áudio já como PCM
    var feed: ((AVAudioPCMBuffer) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        request?.appendAudioSampleBuffer(sampleBuffer)
        if let feed, let pcm = Self.pcm(sampleBuffer) { feed(pcm) }
    }

    static func pcm(_ sb: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard var asbd = sb.formatDescription?.audioStreamBasicDescription,
              let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(sb.numSamples)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(frames), into: buf.mutableAudioBufferList)
        return status == noErr ? buf : nil
    }
}

/// O transcritor do macOS 26 em tempo real: resultados provisórios trocam a frase atual, os finais vão se juntando
@available(macOS 26, *)
final class ModernCaptionEngine: @unchecked Sendable {
    private let onText: (String) -> Void
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var results: Task<Void, Never>?
    private let lock = NSLock()

    init(onText: @escaping (String) -> Void) { self.onText = onText }

    func start(locale: Locale) async throws {
        guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { throw CocoaError(.featureUnsupported) }
        let transcriber = SpeechTranscriber(locale: loc, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        // O modelo do idioma é baixado pelo macOS na primeira vez
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await req.downloadAndInstall() }
        format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        input = cont
        let a = SpeechAnalyzer(modules: [transcriber])
        analyzer = a
        results = Task { [onText] in
            var done = ""
            do {
                for try await r in transcriber.results {
                    let t = String(r.text.characters)
                    if r.isFinal {
                        done = LiveCaptions.tail(done + t, max: 400)
                        onText(done)
                    } else {
                        onText(done + t)
                    }
                }
            } catch {}
        }
        try await a.start(inputSequence: stream)
    }

    /// Converte para o formato que o transcritor quer (16 kHz mono, em geral) e entrega
    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let format, let input else { return }
        if buffer.format == format { input.yield(AnalyzerInput(buffer: buffer)); return }
        if converter == nil || converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: format) }
        guard let converter else { return }
        let ratio = format.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32) else { return }
        var given = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return buffer
        }
        if err == nil, out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
    }

    func stop() {
        input?.finish()
        input = nil
        results?.cancel()
        let a = analyzer
        analyzer = nil
        Task { await a?.cancelAndFinishNow() }
    }
}

/// Idiomas das legendas: o que se fala e para o que traduzir
enum CaptionLanguages {
    static let spoken: [(code: String, name: String)] = Transcriber.languages
    static let targets: [(code: String, name: String)] = [
        ("", "—"), ("pt", "Português"), ("en", "English"), ("es", "Español"), ("de", "Deutsch"), ("zh", "中文"),
        ("fr", "Français"), ("it", "Italiano"), ("ja", "日本語"),
    ]
}

struct CaptionsView: View {
    @ObservedObject var model: LiveCaptions
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(model.running ? Color.red : Color.gray).frame(width: 7, height: 7)
                Picker("", selection: $model.source) {
                    Label(L("Som do Mac"), systemImage: "speaker.wave.2.fill").tag(LiveCaptions.Source.system)
                    Label(L("Microfone"), systemImage: "mic.fill").tag(LiveCaptions.Source.mic)
                }
                .labelsHidden().fixedSize()
                Picker("", selection: $model.from) {
                    ForEach(CaptionLanguages.spoken, id: \.code) { Text($0.name).tag($0.code) }
                }
                .labelsHidden().fixedSize()
                if LiveCaptions.canTranslate {
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                    Picker("", selection: $model.to) {
                        ForEach(CaptionLanguages.targets, id: \.code) { Text($0.code.isEmpty ? L("Sem tradução") : $0.name).tag($0.code) }
                    }
                    .labelsHidden().fixedSize()
                }
                Spacer()
                Button { model.running ? model.stop(keepPanel: true) : model.start() } label: {
                    Image(systemName: model.running ? "pause.fill" : "play.fill").frame(width: 22, height: 22)
                }
                .buttonStyle(.plain).help(model.running ? L("Pausar") : L("Continuar"))
                Button { model.stop() } label: { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help(L("Fechar"))
            }
            .controlSize(.small)
            .opacity(hover || !model.running ? 1 : 0.35)

            if let s = model.status {
                Text(s).font(.system(size: 13)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !model.translated.isEmpty {
                Text(model.original).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                Text(model.translated).font(.system(size: 20, weight: .semibold)).lineLimit(2)
            } else {
                Text(model.original.isEmpty ? (model.running ? L("Ouvindo…") : " ") : model.original)
                    .font(.system(size: 20, weight: .semibold)).lineLimit(3)
                    .foregroundStyle(model.original.isEmpty ? .white.opacity(0.5) : .white)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.78)))
        .onHover { hover = $0 }
        .environment(\.colorScheme, .dark)
    }
}
