// Gera Resources/AppIcon.icns: gradiente + símbolo SF
import AppKit
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let set = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for s in sizes {
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        let inset = r.insetBy(dx: r.width * 0.09, dy: r.height * 0.09)
        let path = NSBezierPath(roundedRect: inset, xRadius: inset.width * 0.225, yRadius: inset.width * 0.225)
        NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.42, blue: 1, alpha: 1),
                            NSColor(srgbRed: 0.62, green: 0.25, blue: 0.95, alpha: 1)])!.draw(in: path, angle: -60)
        let cfg = NSImage.SymbolConfiguration(pointSize: inset.width * 0.5, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let sym = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let sz = sym.size
            sym.draw(in: NSRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height))
        }
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    let png = rep.representation(using: .png, properties: [:])!
    for (scale, name) in [(1, "icon_\(s)x\(s).png"), (2, "icon_\(s/2)x\(s/2)@2x.png")] where s / scale >= 16 && s <= 1024 {
        if scale == 2 && s == 16 { continue }
        try! png.write(to: set.appendingPathComponent(name))
    }
}
