// Gera o fundo da janela de instalação do .dmg (640×400, com versão @2x).
//   swift scripts/make-dmg-background.swift Resources/dmg
//
// Tom médio de propósito: o Finder escreve os nomes dos ícones em preto (tema claro)
// ou branco (tema escuro), e os dois precisam continuar legíveis.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let size = NSSize(width: 640, height: 400)
// Centros dos ícones (coordenadas do Finder, origem no topo), iguais às do dmg-settings.py
let appX: CGFloat = 170, appsX: CGFloat = 470, iconY: CGFloat = 205

func draw(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(origin: .zero, size: size)

    // Fundo: gradiente da marca em tom médio + brilhos suaves
    NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.40, blue: 0.95, alpha: 1),
                        NSColor(srgbRed: 0.58, green: 0.36, blue: 0.90, alpha: 1)])!.draw(in: r, angle: -35)
    for (c, x, y, rad) in [(NSColor.white.withAlphaComponent(0.16), 120.0, 330.0, 260.0),
                           (NSColor(srgbRed: 0.30, green: 0.20, blue: 0.70, alpha: 0.35), 560.0, 60.0, 300.0)] {
        NSGradient(colors: [c, c.withAlphaComponent(0)])!
            .draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: rad, options: [])
    }

    // Placas atrás dos ícones
    for x in [appX, appsX] {
        let plate = NSBezierPath(roundedRect: NSRect(x: x - 92, y: size.height - iconY - 98, width: 184, height: 184),
                                 xRadius: 36, yRadius: 36)
        NSColor.white.withAlphaComponent(0.10).setFill()
        plate.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        plate.lineWidth = 1
        plate.stroke()
    }

    // Seta tracejada entre os ícones
    let y = size.height - iconY + 10
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: appX + 104, y: y))
    arrow.line(to: NSPoint(x: appsX - 112, y: y))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.setLineDash([2, 10], count: 2, phase: 0)
    NSColor.white.withAlphaComponent(0.85).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: appsX - 124, y: y + 13))
    head.line(to: NSPoint(x: appsX - 108, y: y))
    head.line(to: NSPoint(x: appsX - 124, y: y - 13))
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Textos
    func text(_ s: String, _ font: NSFont, _ alpha: CGFloat, y: CGFloat) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(alpha), .shadow: shadow]
        let w = (s as NSString).size(withAttributes: attrs).width
        (s as NSString).draw(at: NSPoint(x: (size.width - w) / 2, y: y), withAttributes: attrs)
    }
    text("Install Menew", .systemFont(ofSize: 24, weight: .bold), 1, y: size.height - 62)
    text("Drag Menew into the Applications folder", .systemFont(ofSize: 13, weight: .medium), 0.85, y: 34)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! draw(scale: 1).write(to: out.appendingPathComponent("background.png"))
try! draw(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
print("ok")
