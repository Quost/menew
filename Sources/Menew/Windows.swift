import AppKit
import Carbon
import SwiftUI

/// Onde a janela vai parar, em frações da área útil da tela (origem no canto de cima à esquerda)
enum WindowLayout: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, center, restore, nextDisplay

    var id: String { rawValue }

    /// nil para os que não são um retângulo fixo (centralizar, restaurar, outra tela)
    var unit: CGRect? {
        switch self {
        case .leftHalf: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .firstThird: CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .centerThird: CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .lastThird: CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .firstTwoThirds: CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .lastTwoThirds: CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        case .maximize: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center, .restore, .nextDisplay: nil
        }
    }

    var title: String {
        switch self {
        case .leftHalf: L("Metade esquerda")
        case .rightHalf: L("Metade direita")
        case .topHalf: L("Metade de cima")
        case .bottomHalf: L("Metade de baixo")
        case .topLeft: L("Canto superior esquerdo")
        case .topRight: L("Canto superior direito")
        case .bottomLeft: L("Canto inferior esquerdo")
        case .bottomRight: L("Canto inferior direito")
        case .firstThird: L("Terço esquerdo")
        case .centerThird: L("Terço do meio")
        case .lastThird: L("Terço direito")
        case .firstTwoThirds: L("Dois terços à esquerda")
        case .lastTwoThirds: L("Dois terços à direita")
        case .maximize: L("Maximizar")
        case .center: L("Centralizar")
        case .restore: L("Voltar ao tamanho anterior")
        case .nextDisplay: L("Mandar para a outra tela")
        }
    }

    /// Mesmos atalhos do Rectangle, que muita gente já conhece: ⌃⌥ + tecla
    var shortcut: (keyCode: Int, key: String, extraCmd: Bool) {
        switch self {
        case .leftHalf: (kVK_LeftArrow, "←", false)
        case .rightHalf: (kVK_RightArrow, "→", false)
        case .topHalf: (kVK_UpArrow, "↑", false)
        case .bottomHalf: (kVK_DownArrow, "↓", false)
        case .topLeft: (kVK_ANSI_U, "U", false)
        case .topRight: (kVK_ANSI_I, "I", false)
        case .bottomLeft: (kVK_ANSI_J, "J", false)
        case .bottomRight: (kVK_ANSI_K, "K", false)
        case .firstThird: (kVK_ANSI_D, "D", false)
        case .centerThird: (kVK_ANSI_F, "F", false)
        case .lastThird: (kVK_ANSI_G, "G", false)
        case .firstTwoThirds: (kVK_ANSI_E, "E", false)
        case .lastTwoThirds: (kVK_ANSI_T, "T", false)
        case .maximize: (kVK_Return, "↩", false)
        case .center: (kVK_ANSI_C, "C", false)
        case .restore: (kVK_Delete, "⌫", false)
        case .nextDisplay: (kVK_RightArrow, "→", true)
        }
    }

    var shortcutDisplay: String { (shortcut.extraCmd ? "⌃⌥⌘" : "⌃⌥") + shortcut.key }
}

/// Move e redimensiona a janela da frente pela API de Acessibilidade
@MainActor
final class WindowManager {
    static let shared = WindowManager()
    static let shortcutsKey = "windowShortcuts"

    /// O último app que não é o Menew: é a janela dele que os botões do menu movem
    private var lastApp: NSRunningApplication?
    /// Tamanho antes do primeiro encaixe, por janela, para "voltar ao tamanho anterior"
    private var saved: [WindowKey: CGRect] = [:]
    private var hotKeys: [HotKey] = []

    private struct WindowKey: Hashable {
        let pid: pid_t
        let hash: CFHashCode
    }

    private init() {
        lastApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app, app.bundleIdentifier != Bundle.main.bundleIdentifier { WindowManager.shared.lastApp = app }
            }
        }
    }

    static var shortcutsOn: Bool { UserDefaults.standard.object(forKey: shortcutsKey) as? Bool ?? true }

    /// Registra ⌃⌥ + tecla para cada encaixe (ids a partir de 100, longe dos outros atalhos)
    func registerHotKeys() {
        hotKeys = []
        guard Self.shortcutsOn, Module.actions.isOn else { return }
        hotKeys = WindowLayout.allCases.enumerated().map { i, layout in
            let s = layout.shortcut
            var mods = UInt32(controlKey | optionKey)
            if s.extraCmd { mods |= UInt32(cmdKey) }
            return HotKey(keyCode: UInt32(s.keyCode), modifiers: mods, id: UInt32(100 + i)) {
                MainActor.assumeIsolated { WindowManager.shared.apply(layout) }
            }
        }
    }

    func suspendHotKeys() { hotKeys = [] }

    /// `fromMenu`: veio de um botão no menu do Menew, então age no app que estava na frente antes dele
    func apply(_ layout: WindowLayout, fromMenu: Bool = false) {
        guard AXIsProcessTrusted() else {
            ClipboardManager.requestAccessibility()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        let app = (fromMenu || front?.bundleIdentifier == Bundle.main.bundleIdentifier) ? lastApp : front
        guard let app, let window = focusedWindow(of: app.processIdentifier),
              let current = frame(of: window) else { NSSound.beep(); return }
        if fromMenu { app.activate() }

        let key = WindowKey(pid: app.processIdentifier, hash: CFHash(window))
        let screen = screenContaining(current)
        let area = axFrame(of: screen.visibleFrame)

        let target: CGRect
        switch layout {
        case .restore:
            guard let old = saved.removeValue(forKey: key) else { return }
            target = old
        case .center:
            let size = CGSize(width: min(current.width, area.width), height: min(current.height, area.height))
            target = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        case .nextDisplay:
            let screens = NSScreen.screens
            guard screens.count > 1, let i = screens.firstIndex(of: screen) else { NSSound.beep(); return }
            let next = axFrame(of: screens[(i + 1) % screens.count].visibleFrame)
            // Mesma posição e tamanho proporcionais na outra tela
            let rel = CGRect(x: (current.minX - area.minX) / area.width, y: (current.minY - area.minY) / area.height,
                             width: current.width / area.width, height: current.height / area.height)
            target = CGRect(x: next.minX + rel.minX * next.width, y: next.minY + rel.minY * next.height,
                            width: min(rel.width, 1) * next.width, height: min(rel.height, 1) * next.height)
        default:
            guard let u = layout.unit else { return }
            target = CGRect(x: area.minX + u.minX * area.width, y: area.minY + u.minY * area.height,
                            width: u.width * area.width, height: u.height * area.height).integral
        }
        if layout != .restore, saved[key] == nil { saved[key] = current }
        setFrame(target, of: window)
    }

    // MARK: Acessibilidade

    private func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success, let value {
            return (value as! AXUIElement)
        }
        // Alguns apps só respondem pela lista de janelas
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let list = value as? [AXUIElement] { return list.first }
        return nil
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private func setFrame(_ r: CGRect, of window: AXUIElement) {
        var p = r.origin, s = r.size
        guard let pos = AXValueCreate(.cgPoint, &p), let size = AXValueCreate(.cgSize, &s) else { return }
        // Tamanho, posição e tamanho de novo: sem isso a janela esbarra na borda da tela e fica menor
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
    }

    // MARK: Coordenadas (AppKit tem origem embaixo; Acessibilidade, em cima da tela principal)

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func axFrame(of r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private func screenContaining(_ axRect: CGRect) -> NSScreen {
        let center = CGPoint(x: axRect.midX, y: primaryHeight - axRect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

/// Miniatura da tela com a parte que a janela vai ocupar
struct LayoutIcon: View {
    let layout: WindowLayout

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                if let u = layout.unit {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.indigo.gradient)
                        .frame(width: max(u.width * w - 3, 2), height: max(u.height * h - 3, 2))
                        .offset(x: u.minX * w + 1.5, y: u.minY * h + 1.5)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.indigo)
                        .frame(width: w, height: h)
                }
            }
        }
        .frame(width: 26, height: 17)
    }

    private var symbol: String {
        switch layout {
        case .center: "arrow.down.right.and.arrow.up.left"
        case .restore: "arrow.uturn.backward"
        default: "arrow.right.to.line"
        }
    }
}
