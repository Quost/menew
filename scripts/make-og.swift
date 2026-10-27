// Gera as imagens de prévia de links (Open Graph, 1200×630) em cada idioma do site.
//   swift scripts/make-og.swift
// Lê o título e o selo de site/i18n/<idioma>.json e as capturas de docs/assets(/<idioma>).
// Saída: docs/assets/og/<idioma>.png
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let W: CGFloat = 1200, H: CGFloat = 630
let indigo = NSColor(srgbRed: 0.36, green: 0.42, blue: 1.0, alpha: 1)
let violet = NSColor(srgbRed: 0.62, green: 0.25, blue: 0.95, alpha: 1)
let icon = NSImage(contentsOf: root.appendingPathComponent("docs/assets/icon.png"))!

/// "Your Mac's menu bar, <br><span class="grad">supercharged.</span>" → ("Your Mac's menu bar,", "supercharged.")
func titleLines(_ html: String) -> (String, String) {
    let parts = html.components(separatedBy: "<br>")
    let strip = { (s: String) in
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespaces)
    }
    return (strip(parts.first ?? html), strip(parts.count > 1 ? parts[1] : ""))
}

func draw(text: String, font: NSFont, color: NSColor? = nil, at p: NSPoint, maxWidth: CGFloat, gradient: Bool = false) {
    var size = font.pointSize
    var attrs: [NSAttributedString.Key: Any] = [:]
    // Diminui a fonte até caber numa linha (títulos longos em alemão, por exemplo)
    repeat {
        attrs = [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .kern: -size * 0.025,
                 .foregroundColor: color ?? NSColor.white]
        if font.fontName.contains("Semibold") || color != nil && !gradient {
            attrs[.font] = NSFont.systemFont(ofSize: size, weight: font.pointSize < 30 ? .semibold : .heavy)
        }
        if (text as NSString).size(withAttributes: attrs).width <= maxWidth { break }
        size -= 2
    } while size > 20
    let s = (text as NSString).size(withAttributes: attrs)
    if gradient {
        let img = NSImage(size: s, flipped: false) { b in
            (text as NSString).draw(at: .zero, withAttributes: attrs.merging([.foregroundColor: NSColor.black]) { $1 })
            NSGraphicsContext.current?.compositingOperation = .sourceIn
            NSGradient(colors: [indigo, violet])!.draw(in: b, angle: 0)
            return true
        }
        img.draw(at: p, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        (text as NSString).draw(at: p, withAttributes: attrs)
    }
}

func shot(_ image: NSImage, in rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor.black.withAlphaComponent(0.6)
    sh.shadowBlurRadius = 40
    sh.shadowOffset = NSSize(width: 0, height: -14)
    sh.set()
    let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.15).setStroke()
    path.lineWidth = 1.2
    path.stroke()
}

let out = root.appendingPathComponent("docs/assets/og")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for lang in ["en", "pt", "de", "es", "zh"] {
    let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("site/i18n/\(lang).json"))) as! [String: String]
    let (line1, line2) = titleLines(json["h1"]!)
    let badge = json["badge"]!.replacingOccurrences(of: "&amp;", with: "&")
    let shots = root.appendingPathComponent(lang == "en" ? "docs/assets" : "docs/assets/\(lang)")
    let panel = NSImage(contentsOf: shots.appendingPathComponent("panel0-dark.png"))!
    let popover = NSImage(contentsOf: shots.appendingPathComponent("popover-system-dark.png"))!

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Fundo escuro com brilhos da marca
    NSColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
    for (c, x, y, r) in [(violet.withAlphaComponent(0.5), 180.0, 520.0, 520.0), (indigo.withAlphaComponent(0.4), 1000.0, 120.0, 560.0)] {
        NSGradient(colors: [c, c.withAlphaComponent(0)])!
            .draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: r, options: [])
    }

    // Capturas à direita, saindo da borda
    let ps = NSSize(width: 640, height: 640 * panel.size.height / panel.size.width)
    shot(panel, in: NSRect(x: 600, y: 150, width: ps.width, height: ps.height))
    let os = NSSize(width: 250, height: 250 * popover.size.height / popover.size.width)
    shot(popover, in: NSRect(x: 920, y: -40, width: os.width, height: os.height))

    // Texto à esquerda
    let left: CGFloat = 64, textWidth: CGFloat = 520
    icon.draw(in: NSRect(x: left, y: 448, width: 92, height: 92))
    draw(text: "Menew", font: .systemFont(ofSize: 64, weight: .heavy), color: .white, at: NSPoint(x: left + 110, y: 458), maxWidth: 400)
    draw(text: line1, font: .systemFont(ofSize: 44, weight: .heavy), color: .white, at: NSPoint(x: left, y: 330), maxWidth: textWidth)
    draw(text: line2, font: .systemFont(ofSize: 44, weight: .heavy), at: NSPoint(x: left, y: 272), maxWidth: textWidth, gradient: true)

    // Selo "Gratuito e open source · macOS 14+"
    let pillAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white]
    let pw = (badge as NSString).size(withAttributes: pillAttrs).width + 40
    let pill = NSBezierPath(roundedRect: NSRect(x: left, y: 178, width: pw, height: 48), xRadius: 24, yRadius: 24)
    NSGradient(colors: [indigo, violet])!.draw(in: pill, angle: 0)
    (badge as NSString).draw(at: NSPoint(x: left + 20, y: 189), withAttributes: pillAttrs)

    let url: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.6)]
    ("menew.web.app" as NSString).draw(at: NSPoint(x: left, y: 64), withAttributes: url)

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(lang).png"))
    print("docs/assets/og/\(lang).png")
}
