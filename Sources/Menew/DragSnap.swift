import AppKit

/// Encaixar janelas arrastando, como no Rectangle e no Magnet: leve a janela até a borda esquerda ou direita (metade),
/// até o topo (tela cheia) ou até um canto (um quarto). Uma prévia mostra onde ela vai ficar; solte para encaixar.
/// Usa a permissão de Acessibilidade, que o Menew já pede para organizar janelas.
@MainActor
final class DragSnap {
    static let shared = DragSnap()
    static let key = "windowDragSnap"
    /// Apps que já fazem isso: com eles abertos, o Menew não disputa o arraste
    private static let others = ["com.knollsoft.Rectangle", "com.knollsoft.Hookshot", "com.crowdcafe.windowmagnet",
                                 "com.hegenberg.BetterSnapTool", "com.manytricks.Moom"]

    private var monitors: [Any] = []
    private var window: AXUIElement?
    private var startFrame: CGRect?
    private var dragging = false
    private var zone: WindowLayout?
    private var lastCheck = Date.distantPast
    private var preview: NSPanel?

    var isOn: Bool { UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true }

    func refresh() {
        let running = NSWorkspace.shared.runningApplications.contains { Self.others.contains($0.bundleIdentifier ?? "") }
        if isOn, !running, monitors.isEmpty {
            monitors = [
                NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in MainActor.assumeIsolated { DragSnap.shared.down() } },
                NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in MainActor.assumeIsolated { DragSnap.shared.drag() } },
                NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in MainActor.assumeIsolated { DragSnap.shared.up() } },
            ].compactMap { $0 }
        } else if !isOn || running {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            hidePreview()
        }
    }

    /// Guarda a janela da frente: só vira "arrastar janela" se ela se mover sem mudar de tamanho
    private func down() {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { window = nil; return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &value) == .success, let value else { window = nil; return }
        let w = value as! AXUIElement
        window = w
        startFrame = WindowManager.shared.frame(of: w)
        dragging = false
        zone = nil
    }

    private func drag() {
        guard let window, let start = startFrame else { return }
        if !dragging {
            guard Date().timeIntervalSince(lastCheck) > 0.05 else { return }
            lastCheck = Date()
            guard let now = WindowManager.shared.frame(of: window) else { return }
            // Moveu e manteve o tamanho: é a barra de título sendo arrastada (não um redimensionamento)
            guard now.size == start.size, abs(now.minX - start.minX) + abs(now.minY - start.minY) > 4 else { return }
            dragging = true
        }
        let newZone = Self.zone(at: NSEvent.mouseLocation)
        guard newZone != zone else { return }
        zone = newZone
        if let z = newZone, let screen = Self.screen(at: NSEvent.mouseLocation) { showPreview(Self.appKitRect(z, on: screen)) } else { hidePreview() }
    }

    private func up() {
        defer { window = nil; dragging = false; zone = nil; hidePreview() }
        guard dragging, let window, let z = zone, let screen = Self.screen(at: NSEvent.mouseLocation) else { return }
        let target = WindowManager.shared.axFrame(of: Self.appKitRect(z, on: screen))
        // Um instante para o macOS terminar o arraste antes de reposicionar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { WindowManager.shared.setFrame(target, of: window) }
    }

    // MARK: Zonas

    /// Borda esquerda/direita = metade; topo = tela cheia; cantos = um quarto
    static func zone(at p: NSPoint) -> WindowLayout? {
        guard let s = screen(at: p) else { return nil }
        let f = s.frame, edge: CGFloat = 6, corner: CGFloat = 80
        let left = p.x <= f.minX + edge, right = p.x >= f.maxX - edge
        let top = p.y >= f.maxY - edge, bottom = p.y <= f.minY + edge
        let nearTop = p.y >= f.maxY - corner, nearBottom = p.y <= f.minY + corner
        let nearLeft = p.x <= f.minX + corner, nearRight = p.x >= f.maxX - corner
        if (left && nearTop) || (top && nearLeft) { return .topLeft }
        if (right && nearTop) || (top && nearRight) { return .topRight }
        if (left && nearBottom) || (bottom && nearLeft) { return .bottomLeft }
        if (right && nearBottom) || (bottom && nearRight) { return .bottomRight }
        if left { return .leftHalf }
        if right { return .rightHalf }
        if top { return .maximize }
        return nil
    }

    static func screen(at p: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }

    /// Retângulo da zona na área útil da tela (sem barra de menus e Dock), em coordenadas do AppKit
    static func appKitRect(_ z: WindowLayout, on screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame
        let u = z == .maximize ? CGRect(x: 0, y: 0, width: 1, height: 1) : (z.unit ?? CGRect(x: 0, y: 0, width: 1, height: 1))
        // `unit` tem origem em cima; o AppKit, embaixo
        return NSRect(x: v.minX + u.minX * v.width, y: v.maxY - (u.minY + u.height) * v.height,
                      width: u.width * v.width, height: u.height * v.height).integral
    }

    // MARK: Prévia

    private func showPreview(_ r: NSRect) {
        let p = preview ?? {
            let p = NSPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.ignoresMouseEvents = true
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            let v = NSView()
            v.wantsLayer = true
            v.layer?.cornerRadius = 12
            v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
            v.layer?.borderWidth = 2
            p.contentView = v
            return p
        }()
        preview = p
        p.setFrame(r.insetBy(dx: 6, dy: 6), display: true, animate: p.isVisible)
        p.orderFrontRegardless()
    }

    private func hidePreview() { preview?.orderOut(nil) }
}
