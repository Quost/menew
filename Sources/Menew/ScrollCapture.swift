import AppKit
import ScreenCaptureKit

/// Captura com rolagem: escolha a área de uma página ou lista e o Menew rola sozinho, fotografa cada pedaço
/// e junta tudo numa imagem comprida, que abre no editor de capturas. Esc para antes.
@MainActor
enum ScrollCapture {
    static let maxFrames = 40
    static let maxHeight = 16_000
    private static var running = false
    private static var cancel = false

    static func start() {
        guard !running, ScreenCapture.hasAccess() else { return }
        guard AXIsProcessTrusted() else {
            HUD.show(icon: "hand.raised.fill", color: .orange, text: L("Libere o Menew em Acessibilidade"), duration: 2.5)
            return
        }
        RegionPicker.pick(hint: L("Arraste sobre a área que rola · esc cancela")) { picked in
            guard let (rect, screen) = picked else { return }
            Task { await run(rect: rect, screen: screen) }
        }
    }

    private static func run(rect: CGRect, screen: NSScreen) async {
        running = true
        cancel = false
        defer { running = false }
        let esc = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { MainActor.assumeIsolated { ScrollCapture.cancel = true } }
        }
        defer { if let esc { NSEvent.removeMonitor(esc) } }
        HUD.show(icon: "arrow.down.doc", color: .blue, text: L("Rolando e capturando… esc para"), duration: nil)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else { return }
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = ScreenRecorder.sourceRect(rect, in: screen.frame)
            config.width = Int(rect.width * screen.backingScaleFactor)
            config.height = Int(rect.height * screen.backingScaleFactor)
            config.showsCursor = false

            // O mouse precisa estar sobre a área para a rolagem ir para ela
            let primary = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let center = CGPoint(x: rect.midX, y: primary - rect.midY)
            CGWarpMouseCursorPosition(center)

            var stitcher = Stitcher()
            var frames = 0
            while frames < maxFrames, !cancel {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                frames += 1
                guard stitcher.add(image) else { break }
                if stitcher.height >= maxHeight { break }
                let step = Int32(rect.height * 0.6)
                let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0)
                scroll?.location = center
                scroll?.post(tap: .cghidEventTap)
                try await Task.sleep(for: .milliseconds(450))
            }
            HUD.hide()
            guard let result = stitcher.image() else { throw CancellationError() }
            ScreenCapture.edit(NSImage(cgImage: result, size: NSSize(width: CGFloat(result.width) / screen.backingScaleFactor,
                                                                     height: CGFloat(result.height) / screen.backingScaleFactor)))
        } catch {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para capturar com rolagem"), duration: 2.5)
        }
    }
}

/// Junta capturas sucessivas de uma área que rola: acha quanto o conteúdo subiu comparando linhas de pixels
/// e acrescenta só as linhas novas. Cabeçalhos e rodapés fixos (iguais nas duas capturas) entram uma vez só.
struct Stitcher {
    struct Frame { let pixels: [UInt32]; let rows: [UInt64]; let flat: [Bool] }
    private(set) var frames: [(image: CGImage, frame: Frame)] = []
    /// Pedaços da imagem final: de qual captura e quais linhas
    private(set) var pieces: [(index: Int, from: Int, to: Int)] = []
    private var fixedBottom = 0
    private(set) var width = 0
    private var rowCount = 0

    var height: Int { pieces.reduce(0) { $0 + $1.to - $1.from } + fixedBottom }

    /// false = não rolou mais (chegou ao fim)
    mutating func add(_ image: CGImage) -> Bool {
        guard let f = Self.analyze(image) else { return false }
        defer { frames.append((image, f)) }
        guard let prev = frames.last?.frame else {
            width = image.width
            rowCount = image.height
            pieces = [(0, 0, image.height)]
            return true
        }
        guard image.width == width, image.height == rowCount, let (offset, top, bottom) = Self.offset(prev, f) else { return false }
        // A captura anterior terminava no rodapé fixo; tira ele de lá e põe as linhas novas antes dele
        if let last = pieces.indices.last { pieces[last].to = min(pieces[last].to, rowCount - bottom) }
        _ = top
        fixedBottom = bottom
        pieces.append((frames.count, rowCount - bottom - offset, rowCount - bottom))
        return true
    }

    func image() -> CGImage? {
        guard let lastIndex = frames.indices.last, width > 0 else { return nil }
        var all = pieces
        if fixedBottom > 0 { all.append((lastIndex, rowCount - fixedBottom, rowCount)) }
        let total = all.reduce(0) { $0 + $1.to - $1.from }
        guard total > 0, let ctx = CGContext(data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // O CGContext tem origem embaixo: desenha de cima para baixo descontando a altura
        var y = total
        for p in all {
            let h = p.to - p.from
            y -= h
            guard let crop = frames[p.index].image.cropping(to: CGRect(x: 0, y: p.from, width: width, height: h)) else { continue }
            ctx.draw(crop, in: CGRect(x: 0, y: y, width: width, height: h))
        }
        return ctx.makeImage()
    }

    /// Um hash por linha (sem a faixa da direita, onde aparece a barra de rolagem) e se a linha é de uma cor só
    static func analyze(_ image: CGImage) -> Frame? {
        let w = image.width, h = image.height
        var pixels = [UInt32](repeating: 0, count: w * h)
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        let usable = max(1, w - min(40, w / 8))
        var rows = [UInt64](repeating: 0, count: h), flat = [Bool](repeating: true, count: h)
        for r in 0..<h {
            var hash: UInt64 = 1469598103934665603
            let base = r * w, first = pixels[base]
            var same = true
            for x in 0..<usable {
                let p = pixels[base + x]
                hash = (hash ^ UInt64(p)) &* 1099511628211
                if same, p != first { same = false }
            }
            rows[r] = hash
            flat[r] = same
        }
        return Frame(pixels: [], rows: rows, flat: flat)
    }

    /// Quanto o conteúdo subiu entre as duas capturas; nil se não mudou (fim da rolagem)
    static func offset(_ a: Frame, _ b: Frame) -> (Int, Int, Int)? {
        let h = a.rows.count
        guard h == b.rows.count, h > 20 else { return nil }
        var top = 0
        while top < h, a.rows[top] == b.rows[top] { top += 1 }
        guard top < h else { return nil } // igual: não rolou
        var bottom = 0
        while bottom < h - top, a.rows[h - 1 - bottom] == b.rows[h - 1 - bottom] { bottom += 1 }
        let lo = top, hi = h - bottom
        guard hi - lo > 10 else { return nil }
        var best: (offset: Int, score: Double) = (0, 0)
        for o in 1..<(hi - lo - 5) {
            var match = 0, considered = 0
            for r in lo..<(hi - o) where !b.flat[r] {
                considered += 1
                if b.rows[r] == a.rows[r + o] { match += 1 }
            }
            guard considered >= 8 else { continue }
            let score = Double(match) / Double(considered)
            if score > best.score { best = (o, score) }
        }
        guard best.score >= 0.85 else { return nil }
        return (best.offset, top, bottom)
    }
}
