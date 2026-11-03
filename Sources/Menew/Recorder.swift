import AVFoundation
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: Escolher a área

/// Escurece as telas e deixa arrastar um retângulo; um clique sem arrastar pega a tela inteira, esc cancela.
/// Devolve o retângulo em coordenadas do AppKit e a tela dele.
@MainActor
final class RegionPicker {
    private static var current: RegionPicker?
    private var panels: [NSPanel] = []
    private var done: ((CGRect, NSScreen)?) -> Void = { _ in }

    static func pick(hint: String, _ done: @escaping ((CGRect, NSScreen)?) -> Void) {
        current?.finish(nil)
        let p = RegionPicker()
        p.done = done
        current = p
        p.show(hint: hint)
    }

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func show(hint: String) {
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        for screen in NSScreen.screens {
            let p = KeyPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = RegionView(frame: NSRect(origin: .zero, size: screen.frame.size), hint: hint)
            v.onDone = { [weak self] r in
                guard let self else { return }
                guard let r else { return self.finish(nil) }
                // Clique sem arrastar: a tela toda
                let local = r.width < 8 || r.height < 8 ? NSRect(origin: .zero, size: screen.frame.size) : r
                self.finish((local.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY).integral, screen))
            }
            p.contentView = v
            p.setFrame(screen.frame, display: true)
            p.orderFrontRegardless()
            panels.append(p)
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        (panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first)?.makeKey()
        NSCursor.crosshair.push()
    }

    private func finish(_ result: (CGRect, NSScreen)?) {
        NSCursor.pop()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        Self.current = nil
        // Espera as camadas escuras sumirem da tela antes de gravar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.done(result) }
    }

    private final class RegionView: NSView {
        var onDone: (NSRect?) -> Void = { _ in }
        private var start: NSPoint?
        private var rect: NSRect?
        private let hint: String

        init(frame: NSRect, hint: String) {
            self.hint = hint
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onDone(nil) } // esc
            else if event.keyCode == 36 { onDone(.zero) } // ↩ = tela inteira
        }

        override func mouseDown(with event: NSEvent) {
            start = convert(event.locationInWindow, from: nil)
            rect = nil
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            let p = convert(event.locationInWindow, from: nil)
            rect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) { onDone(rect ?? .zero) }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.3).setFill()
            bounds.fill()
            if let rect {
                NSColor.clear.setFill()
                rect.fill(using: .copy)
                NSColor.controlAccentColor.setStroke()
                let path = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
                path.lineWidth = 2
                path.stroke()
                let size = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
                size.draw(at: NSPoint(x: rect.minX + 4, y: max(4, rect.minY - 20)),
                          withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
            } else {
                let text = hint as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white]
                let s = text.size(withAttributes: attrs)
                let box = NSRect(x: bounds.midX - s.width / 2 - 16, y: bounds.midY - s.height / 2 - 10, width: s.width + 32, height: s.height + 20)
                NSColor.black.withAlphaComponent(0.6).setFill()
                NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
                text.draw(at: NSPoint(x: box.minX + 16, y: box.minY + 10), withAttributes: attrs)
            }
        }
    }
}

// MARK: Gravação

/// Grava uma área da tela em vídeo (.mov) ou GIF, com ScreenCaptureKit. As janelas do Menew ficam fora da gravação.
/// O arquivo vai para a Mesa, como as capturas do macOS.
@MainActor
final class ScreenRecorder: ObservableObject {
    static let shared = ScreenRecorder()
    /// GIF fica pesado rápido: para sozinho neste tempo
    static let gifLimit: TimeInterval = 30

    @Published private(set) var isRecording = false
    @Published private(set) var started = Date()

    /// Som no vídeo: nenhum (padrão), microfone, som do Mac ou os dois
    static let soundKey = "screenRecordingSound"
    static let transcribeKey = "screenRecordingTranscribe"
    var sound: RecordingStore.Source? { RecordingStore.Source(rawValue: UserDefaults.standard.string(forKey: Self.soundKey) ?? "") }
    /// Com som, o áudio também vai para Gravações e vira transcrição e ata
    var transcribes: Bool { UserDefaults.standard.object(forKey: Self.transcribeKey) as? Bool ?? true }
    private var audioFiles: (mic: URL?, system: URL?) = (nil, nil)
    /// Onde os arquivos ficam (a Mesa); os testes trocam
    var folder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    var revealsInFinder = true
    private var stream: SCStream?
    private var sink: FrameSink?
    private var file: URL?
    private var gif = false
    private var control: NSPanel?
    private var limitTimer: Timer?

    func start(gif: Bool) {
        guard !isRecording else { return stop() }
        guard ScreenCapture.hasAccess() else { return }
        RegionPicker.pick(hint: gif ? L("Arraste para escolher a área do GIF · ↩ tela inteira · esc cancela")
                                    : L("Arraste para escolher a área da gravação · ↩ tela inteira · esc cancela")) { [weak self] picked in
            guard let self, let (rect, screen) = picked else { return }
            Task { await self.begin(rect: rect, screen: screen, gif: gif) }
        }
    }

    func begin(rect: CGRect, screen: NSScreen, gif: Bool) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            // Sem telas na lista (tela bloqueada, por exemplo): cai no aviso de erro
            guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else { throw CancellationError() }
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let scale = screen.backingScaleFactor
            let source = Self.sourceRect(rect, in: screen.frame)
            let config = SCStreamConfiguration()
            config.sourceRect = source
            // H.264 pede largura e altura pares
            let w = Int(source.width * scale) / 2 * 2, h = Int(source.height * scale) / 2 * 2
            config.width = w
            config.height = h
            config.minimumFrameInterval = CMTime(value: 1, timescale: gif ? 15 : 30)
            config.showsCursor = true
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 6

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("menew-rec-\(UUID().uuidString).mov")
            // Som: o do Mac pelo próprio ScreenCaptureKit; o microfone também (macOS 15 ou mais novo)
            let sound = gif ? nil : self.sound
            var wantsMic = sound == .mic || sound == .both
            let wantsSystem = sound == .system || sound == .both
            if wantsSystem {
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48_000
                config.channelCount = 2
            }
            if wantsMic {
                if #available(macOS 15, *) { config.captureMicrophone = true } else {
                    wantsMic = false
                    HUD.show(icon: "mic.slash", color: .orange, text: L("Gravar o microfone junto precisa do macOS 15"), duration: 2.5)
                }
            }
            // Cópias só do áudio, para transcrever depois (separadas: você e os outros)
            var micAudio: URL?, sysAudio: URL?
            if transcribes, let dir = RecordingStore.shared.dir {
                let id = UUID().uuidString
                if wantsMic { micAudio = dir.appendingPathComponent("\(id)-mic.m4a") }
                if wantsSystem { sysAudio = dir.appendingPathComponent("\(id)-system.m4a") }
            }
            audioFiles = (micAudio, sysAudio)
            let sink = try FrameSink(url: url, width: w, height: h, mic: wantsMic, system: wantsSystem, micCopy: micAudio, systemCopy: sysAudio)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            if wantsSystem { try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue) }
            if wantsMic, #available(macOS 15, *) { try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sink.queue) }
            try await stream.startCapture()
            self.stream = stream
            self.sink = sink
            self.file = url
            self.gif = gif
            started = Date()
            isRecording = true
            showControl(near: rect, on: screen)
            if gif {
                limitTimer = Timer.scheduledTimer(withTimeInterval: Self.gifLimit, repeats: false) { _ in
                    MainActor.assumeIsolated { ScreenRecorder.shared.stop() }
                }
            }
        } catch {
            lastError = error.localizedDescription
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para gravar a tela"), duration: 2.5)
        }
    }
    private(set) var lastError: String?

    /// Retângulo do AppKit (origem embaixo, global) → retângulo na tela, com origem em cima, em pontos
    nonisolated static func sourceRect(_ r: CGRect, in screen: CGRect) -> CGRect {
        CGRect(x: r.minX - screen.minX, y: screen.maxY - r.maxY, width: r.width, height: r.height)
    }

    func stop() {
        guard isRecording, let stream, let sink, let file else { return }
        isRecording = false
        limitTimer?.invalidate()
        control?.orderOut(nil)
        control = nil
        let gif = self.gif
        Task {
            try? await stream.stopCapture()
            await sink.finish()
            self.stream = nil
            self.sink = nil
            let name = L("Gravação %@", Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second())
                .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "."))
            let dest = self.folder.appendingPathComponent(name + (gif ? ".gif" : ".mov"))
            let ok: Bool
            if gif {
                HUD.show(icon: "hourglass", color: .orange, text: L("Criando o GIF…"), duration: nil)
                ok = await Task.detached(priority: .userInitiated) { GIFMaker.make(from: file, to: dest) }.value
                try? FileManager.default.removeItem(at: file)
            } else {
                ok = (try? FileManager.default.moveItem(at: file, to: dest)) != nil
            }
            let duration = Date().timeIntervalSince(self.started)
            let audio = self.audioFiles
            self.audioFiles = (nil, nil)
            if ok, !gif, audio.mic != nil || audio.system != nil {
                // O áudio do vídeo vira uma gravação com ata, ligada ao vídeo
                RecordingStore.shared.importScreenRecording(mic: audio.mic, system: audio.system, video: dest, duration: duration)
            }
            if ok {
                HUD.show(icon: "checkmark.circle.fill", color: .green, text: gif ? L("GIF salvo na Mesa") : L("Gravação salva na Mesa"))
                if self.revealsInFinder { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
            } else {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para gravar a tela"), duration: 2.5)
            }
        }
    }

    /// Botão flutuante de parar, logo abaixo (ou acima) da área gravada; fica fora da gravação
    private func showControl(near rect: CGRect, on screen: NSScreen) {
        let size = NSSize(width: 150, height: 36)
        let below = rect.minY - size.height - 10
        let y = below > screen.visibleFrame.minY ? below : min(rect.maxY + 10, screen.visibleFrame.maxY - size.height)
        let x = min(max(rect.midX - size.width / 2, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let p = NSPanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: RecordingControl(recorder: self))
        p.orderFrontRegardless()
        control = p
    }
}

private struct RecordingControl: View {
    @ObservedObject var recorder: ScreenRecorder

    var body: some View {
        Button { recorder.stop() } label: {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 9, height: 9)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let s = Int(ctx.date.timeIntervalSince(recorder.started))
                    Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                }
                Divider().frame(height: 14)
                Image(systemName: "stop.fill").font(.system(size: 11))
                Text(L("Parar")).font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(.regularMaterial))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Parar gravação"))
    }
}

/// Recebe os quadros (e o som) do ScreenCaptureKit e grava num .mov (H.264 + AAC)
private final class FrameSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "menew.recorder")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var micInput: AVAssetWriterInput?
    private var systemInput: AVAssetWriterInput?
    private let micCopy: AudioFileWriter?
    private let systemCopy: AudioFileWriter?
    private var startedSession = false

    init(url: URL, width: Int, height: Int, mic: Bool = false, system: Bool = false, micCopy: URL? = nil, systemCopy: URL? = nil) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        func audioInput(channels: Int) -> AVAssetWriterInput {
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                                                                          AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 128_000])
            i.expectsMediaDataInRealTime = true
            return i
        }
        if system { let i = audioInput(channels: 2); writer.add(i); systemInput = i }
        if mic { let i = audioInput(channels: 1); writer.add(i); micInput = i }
        self.micCopy = try micCopy.map { try AudioFileWriter(url: $0) }
        self.systemCopy = try systemCopy.map { try AudioFileWriter(url: $0) }
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buffer.isValid else { return }
        if type == .screen {
            guard let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
                  let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            if !startedSession {
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: buffer.presentationTimeStamp)
                startedSession = true
            }
            if input.isReadyForMoreMediaData { input.append(buffer) }
            return
        }
        // Som: só depois do primeiro quadro (o vídeo marca o começo)
        guard startedSession else { return }
        if type == .audio {
            if let i = systemInput, i.isReadyForMoreMediaData { i.append(buffer) }
            if let c = systemCopy, let pcm = CaptionAudioOutput.pcm(buffer) { c.write(pcm) }
        } else if #available(macOS 15, *), type == .microphone {
            if let i = micInput, i.isReadyForMoreMediaData { i.append(buffer) }
            if let c = micCopy, let pcm = CaptionAudioOutput.pcm(buffer) { c.write(pcm) }
        }
    }

    func finish() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                self.micCopy?.close()
                self.systemCopy?.close()
                guard self.startedSession else { return c.resume() }
                self.input.markAsFinished()
                self.micInput?.markAsFinished()
                self.systemInput?.markAsFinished()
                self.writer.finishWriting { c.resume() }
            }
        }
    }
}

/// Vídeo → GIF animado em loop: 10 quadros por segundo, até 720 px de largura
enum GIFMaker {
    static func make(from video: URL, to dest: URL, fps: Double = 10, maxWidth: CGFloat = 720) -> Bool {
        let asset = AVURLAsset(url: video)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration > 0 else { return false }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxWidth, height: maxWidth * 4)
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        let count = max(1, Int(duration * fps))
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, UTType.gif.identifier as CFString, count, nil) else { return false }
        CGImageDestinationSetProperties(out, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        var added = 0
        for i in 0..<count {
            let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            guard let img = try? gen.copyCGImage(at: t, actualTime: nil) else { continue }
            CGImageDestinationAddImage(out, img, frame)
            added += 1
        }
        return added > 0 && CGImageDestinationFinalize(out)
    }
}
