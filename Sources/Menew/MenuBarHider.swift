import AppKit

/// Esconder ícones da barra de menus. Dois ícones entram à esquerda do Menew: um ‹ e uma linha |.
/// Com ⌘ pressionado, a pessoa arrasta para a esquerda da linha os ícones que quer esconder; clicar no ‹ fecha:
/// a linha cresce e empurra esses ícones para fora da tela. Clicar de novo traz todos de volta.
/// Desligado por padrão. Sem permissão nenhuma e nada sai do Mac.
@MainActor
final class MenuBarHider: NSObject {
    static let shared = MenuBarHider()
    static let key = "menubar.hider"
    static let autoKey = "menubar.hider.auto"
    /// Quanto tempo os ícones ficam à mostra antes de esconder de novo sozinhos
    nonisolated static let autoDelay: TimeInterval = 10

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
    static var autoHide: Bool { UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }

    /// O ícone do Menew: a linha tem que ficar à esquerda dele, senão esconderia o próprio Menew
    var menewButton: () -> NSStatusBarButton? = { nil }

    private var toggle: NSStatusItem?
    private var divider: NSStatusItem?
    private(set) var collapsed = false
    private var autoTimer: Timer?
    /// Largura que tira da tela tudo o que está à esquerda da linha, em qualquer monitor
    private static let hiddenLength: CGFloat = 10_000

    /// Liga ou desliga conforme o ajuste
    func refresh() {
        guard Self.isOn else { remove(); return }
        guard toggle == nil else { return }
        // Os novos entram à esquerda dos que já existem: primeiro o ‹, depois a linha, que fica à esquerda dele
        let t = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        t.autosaveName = "MenewHiderToggle"
        if let b = t.button {
            b.target = self
            b.action = #selector(clicked)
            b.setAccessibilityLabel(L("Mostrar ou esconder ícones"))
            b.toolTip = L("Mostrar ou esconder ícones")
        }
        let d = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        d.autosaveName = "MenewHiderDivider"
        if let b = d.button {
            b.image = Self.lineImage
            b.toolTip = L("Segure ⌘ e arraste para a esquerda desta linha os ícones que quer esconder")
            b.setAccessibilityLabel(L("Separador dos ícones escondidos"))
        }
        toggle = t
        divider = d
        collapsed = false
        updateImage()
        // Depois que a barra arruma os ícones: esconde, se a linha estiver no lugar certo
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.collapse(warn: false) }
    }

    private func remove() {
        autoTimer?.invalidate()
        autoTimer = nil
        for item in [toggle, divider].compactMap({ $0 }) { NSStatusBar.system.removeStatusItem(item) }
        toggle = nil
        divider = nil
        collapsed = false
    }

    @objc private func clicked() {
        collapsed ? expand() : collapse(warn: true)
    }

    func expand() {
        guard let divider, collapsed else { return }
        divider.length = NSStatusItem.variableLength
        divider.button?.image = Self.lineImage
        collapsed = false
        updateImage()
        scheduleAutoHide()
    }

    func collapse(warn: Bool) {
        autoTimer?.invalidate()
        autoTimer = nil
        guard let divider, !collapsed else { return }
        guard lineIsLeftOfMenew else {
            if warn {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange,
                         text: L("Arraste a linha | para a esquerda do ícone do Menew (segure ⌘)"), duration: 4)
            }
            return
        }
        divider.button?.image = nil
        divider.length = Self.hiddenLength
        collapsed = true
        updateImage()
    }

    /// A linha está à esquerda do ‹ e do ícone do Menew? Se não, fechar empurraria o Menew para fora da tela.
    private var lineIsLeftOfMenew: Bool {
        guard let x = divider?.button?.window?.frame.minX else { return false }
        let right = [toggle?.button, menewButton()].compactMap { $0?.window?.frame.minX }
        return right.count == 2 && right.allSatisfy { x < $0 }
    }

    /// Esconde de novo depois de um tempo, mas não com o mouse ainda na barra de menus
    private func scheduleAutoHide(after delay: TimeInterval = MenuBarHider.autoDelay) {
        autoTimer?.invalidate()
        guard Self.autoHide else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                let hider = MenuBarHider.shared
                if MenuBarHider.mouseInMenuBar { hider.scheduleAutoHide(after: 3) } else { hider.collapse(warn: false) }
            }
        }
    }

    private static var mouseInMenuBar: Bool {
        let p = NSEvent.mouseLocation
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
        return p.y >= s.frame.maxY - NSStatusBar.system.thickness - 4
    }

    private func updateImage() {
        let name = collapsed ? "chevron.left" : "chevron.right"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        toggle?.button?.image = image
    }

    /// Uma linha fina, da cor dos outros ícones
    private static let lineImage: NSImage = {
        let image = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.75, y: 1, width: 1.5, height: rect.height - 2), xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
