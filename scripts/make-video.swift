// Monta o vídeo de divulgação a partir dos quadros de `Menew --video-frames <frames>`.
//
//   build/Menew.app/Contents/MacOS/Menew --video-frames /tmp/frames -language en
//   swift scripts/make-video.swift /tmp/frames /tmp/video-out
//   ffmpeg -framerate 30 -i /tmp/video-out/%04d.jpg -c:v libx264 -crf 26 -pix_fmt yuv420p -movflags +faststart menew.mp4
//
// Sem texto gravado na imagem (só atalhos e o endereço), para servir nos 5 idiomas do site.
import AppKit

let args = CommandLine.arguments
guard args.count > 2 else { print("usage: make-video.swift <frames> <out>"); exit(1) }
let frames = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let W: CGFloat = 1200, H: CGFloat = 900, fps = 30.0
let barH: CGFloat = 36

func img(_ name: String) -> NSImage { NSImage(contentsOf: frames.appendingPathComponent(name + ".png"))! }
let statusbar = NSImage(contentsOf: repo.appendingPathComponent("docs/assets/statusbar-all.png"))!
let icon = NSImage(contentsOf: repo.appendingPathComponent("docs/assets/icon.png"))!

// Itens na barra: o Menew à esquerda do grupo, depois CPU (posições na imagem statusbar-all, 632×96)
let sbH: CGFloat = 28, sbW = 632 * sbH / 96
let sbX = W - sbW - 110
let menewItem = CGPoint(x: sbX + 30 * sbH / 96, y: H - barH / 2)
let cpuItem = CGPoint(x: sbX + 180 * sbH / 96, y: H - barH / 2)
let notchPoint = CGPoint(x: W / 2, y: H - 14)
let popScale: CGFloat = 1.3
let popW = 400 * popScale
func under(_ x: CGFloat) -> CGFloat { min(max(x - popW / 2, 20), W - 20 - popW) }
let popTopLeft = CGPoint(x: under(menewItem.x), y: H - barH - 6)

// MARK: Linha do tempo (segundos)

func ease(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }
func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
/// 0→1 entre `a` e `a+d`, 1→0 entre `b` e `b+d`
func window(_ t: Double, _ a: Double, _ b: Double, _ d: Double = 0.25) -> Double { min(clamp((t - a) / d), 1 - clamp((t - b) / d)) }

struct Move { let t0, t1: Double; let to: CGPoint }
let start = CGPoint(x: 560, y: 420)
let moves = [
    Move(t0: 0.2, t1: 1.0, to: menewItem),
    Move(t0: 2.6, t1: 3.1, to: CGPoint(x: popTopLeft.x + 0.37 * 520, y: H - barH - 8 - 0.215 * 780)),  // aba Clipboard
    Move(t0: 6.2, t1: 6.7, to: CGPoint(x: popTopLeft.x + 0.6 * 520, y: H - barH - 8 - 0.215 * 780)),   // aba Actions
    Move(t0: 8.6, t1: 9.2, to: CGPoint(x: 420, y: 300)),
    Move(t0: 16.2, t1: 16.9, to: cpuItem),
    Move(t0: 19.6, t1: 20.3, to: notchPoint),
    Move(t0: 23.4, t1: 24.0, to: CGPoint(x: 700, y: 330)),
]
func cursor(_ t: Double) -> CGPoint {
    var p = start
    for m in moves {
        if t >= m.t1 { p = m.to; continue }
        if t > m.t0 { let k = ease((t - m.t0) / (m.t1 - m.t0)); return CGPoint(x: p.x + (m.to.x - p.x) * k, y: p.y + (m.to.y - p.y) * k) }
        break
    }
    return p
}

let total = 27.0
func typed(_ t: Double, from a: Double, count: Int, step: Double = 0.12) -> Int { max(0, min(count, Int((t - a) / step) + 1)) }

// MARK: Desenho

func draw(_ i: NSImage, center: CGPoint? = nil, topLeft: CGPoint? = nil, scale: CGFloat, alpha: Double, radius: CGFloat = 16, shadow: Bool = true) {
    guard alpha > 0.001 else { return }
    let rep = i.representations[0]
    let w = CGFloat(rep.pixelsWide) / 2 * scale, h = CGFloat(rep.pixelsHigh) / 2 * scale
    let r: NSRect = if let c = center { NSRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h) }
                    else { NSRect(x: topLeft!.x, y: topLeft!.y - h, width: w, height: h) }
    NSGraphicsContext.saveGraphicsState()
    if shadow {
        let s = NSShadow(); s.shadowBlurRadius = 28; s.shadowOffset = NSSize(width: 0, height: -10)
        s.shadowColor = NSColor.black.withAlphaComponent(0.4 * alpha); s.set()
        NSColor.black.withAlphaComponent(alpha).setFill(); NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 2), xRadius: radius, yRadius: radius).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).addClip()
    i.draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha)
    NSGraphicsContext.restoreGraphicsState()
}

func keycap(_ text: String, alpha: Double) {
    guard alpha > 0.001 else { return }
    let a = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 34, weight: .semibold),
                                                          .foregroundColor: NSColor.white.withAlphaComponent(alpha)])
    let s = a.size(), r = NSRect(x: W / 2 - s.width / 2 - 22, y: 110, width: s.width + 44, height: s.height + 20)
    NSColor.black.withAlphaComponent(0.55 * alpha).setFill()
    NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
    a.draw(at: NSPoint(x: r.minX + 22, y: r.minY + 10))
}

let background: NSImage = {
    let im = NSImage(size: NSSize(width: W, height: H))
    im.lockFocus()
    NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.13, blue: 0.45, alpha: 1), NSColor(srgbRed: 0.49, green: 0.36, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.93, green: 0.55, blue: 0.75, alpha: 1)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)
    NSColor(white: 0.93, alpha: 0.92).setFill(); NSRect(x: 0, y: H - barH, width: W, height: barH).fill()
    NSAttributedString(string: "  Finder    File    Edit    View    Go    Window    Help",
                       attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.black])
        .draw(at: NSPoint(x: 14, y: H - barH + 9))
    statusbar.draw(in: NSRect(x: sbX, y: H - barH + (barH - sbH) / 2, width: sbW, height: sbH))
    NSAttributedString(string: "Thu 9:41", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.black])
        .draw(at: NSPoint(x: W - 84, y: H - barH + 9))
    NSColor.black.setFill()  // notch
    NSBezierPath(roundedRect: NSRect(x: W / 2 - 100, y: H - 34, width: 200, height: 46), xRadius: 14, yRadius: 14).fill()
    im.unlockFocus()
    return im
}()
let arrow = NSCursor.arrow.image


let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let cache = NSCache<NSString, NSImage>()
func cached(_ n: String) -> NSImage { if let i = cache.object(forKey: n as NSString) { return i }; let i = img(n); cache.setObject(i, forKey: n as NSString); return i }

for f in 0..<Int(total * fps) {
    let t = Double(f) / fps
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    background.draw(in: NSRect(x: 0, y: 0, width: W, height: H))

    // 1. Menu do Menew: Now → Clipboard (busca "github") → Actions
    let popA = window(t, 1.1, 8.7)
    if popA > 0 {
        let name: String
        if t < 3.2 { name = "popover-now" }
        else if t < 6.8 {
            let n = typed(t, from: 3.9, count: 6, step: 0.14)
            name = t < 3.9 ? "popover-clipboard" : "clip-search-\(n)"
        } else { name = "popover-actions" }
        draw(cached(name), topLeft: popTopLeft, scale: popScale, alpha: popA, radius: 14)
    }
    // 2. Palette: ⌃⌥Space, "5 km to mi", depois "timer 10m tea"
    keycap("⌃ ⌥ Space", alpha: window(t, 9.2, 10.6, 0.2))
    let palA = window(t, 9.6, 15.9)
    if palA > 0 {
        let name: String
        if t < 10.4 { name = "palette-0-0" }
        else if t < 13.0 { name = "palette-1-\(typed(t, from: 10.4, count: 10, step: 0.11))" }
        else if t < 13.3 { name = "palette-0-0" }
        else { name = "palette-2-\(typed(t, from: 13.3, count: 13, step: 0.11))" }
        draw(cached(name), center: CGPoint(x: W / 2, y: H / 2 - 10), scale: 1.35, alpha: palA, radius: 18)
    }
    // 3. CPU na barra
    draw(cached("popover-system"), topLeft: CGPoint(x: under(cpuItem.x), y: H - barH - 6), scale: popScale, alpha: window(t, 17.0, 19.5), radius: 14)
    // 4. Notch
    draw(cached("notch"), center: CGPoint(x: W / 2, y: H - 172 * 0.95), scale: 1.9, alpha: window(t, 20.4, 23.3), radius: 30, shadow: false)
    // 5. Fecho: ícone, nome e endereço
    let endA = clamp((t - 24.0) / 0.5)
    if endA > 0 {
        NSColor.black.withAlphaComponent(0.35 * endA).setFill(); NSRect(x: 0, y: 0, width: W, height: H - barH).fill()
        icon.draw(in: NSRect(x: W / 2 - 80, y: H / 2 - 10, width: 160, height: 160), from: .zero, operation: .sourceOver, fraction: endA)
        let p = NSMutableParagraphStyle(); p.alignment = .center
        NSAttributedString(string: "Menew", attributes: [.font: NSFont.systemFont(ofSize: 64, weight: .bold), .paragraphStyle: p,
                                                         .foregroundColor: NSColor.white.withAlphaComponent(endA)])
            .draw(in: NSRect(x: 0, y: H / 2 - 100, width: W, height: 80))
        NSAttributedString(string: "menew.web.app", attributes: [.font: NSFont.systemFont(ofSize: 30, weight: .medium), .paragraphStyle: p,
                                                                 .foregroundColor: NSColor.white.withAlphaComponent(0.85 * endA)])
            .draw(in: NSRect(x: 0, y: H / 2 - 150, width: W, height: 40))
    }
    // Ponteiro (some no fecho)
    if t < 24.0 {
        let c = cursor(t), s = arrow.size
        arrow.draw(in: NSRect(x: c.x - 4, y: c.y - s.height * 1.5 + 4, width: s.width * 1.5, height: s.height * 1.5))
    }
    NSGraphicsContext.restoreGraphicsState()
    let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])!
    try! jpg.write(to: out.appendingPathComponent(String(format: "%04d.jpg", f)))
}
print("\(Int(total * fps)) frames in \(out.path)")
