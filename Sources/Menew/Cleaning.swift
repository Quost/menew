import AppKit
import SwiftUI
import ApplicationServices

/// Modo limpeza: trava o teclado (event tap) ou apaga a tela para enxergar a sujeira.
@MainActor
final class CleaningController: ObservableObject {
    @Published private(set) var keyboardLocked = false
    @Published var secondsLeft = 0

    nonisolated(unsafe) private static var activeTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var windows: [NSWindow] = []
    private var countdown: Timer?

    static let keyboardLockSeconds = 120

    // MARK: Teclado

    /// false = sem permissão de Acessibilidade (o pedido já foi exibido)
    @discardableResult
    func lockKeyboard() -> Bool {
        guard !keyboardLocked else { return true }
        guard AXIsProcessTrusted() else {
            ClipboardManager.requestAccessibility()
            return false
        }
        // keyDown, keyUp, flagsChanged e NSSystemDefined (14: brilho, volume, mídia)
        let types: [UInt32] = [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue, 14]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = CleaningController.activeTap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return nil // engole a tecla
        }, userInfo: nil) else { return false }

        Self.activeTap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyboardLocked = true

        // Destrava sozinho por segurança
        secondsLeft = Self.keyboardLockSeconds
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.secondsLeft -= 1
                if self.secondsLeft <= 0 { self.unlockKeyboard() }
            }
        }
        showOverlay { KeyboardLockView(controller: self) }
        return true
    }

    func unlockKeyboard() {
        countdown?.invalidate()
        countdown = nil
        if let t = Self.activeTap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        Self.activeTap = nil
        source = nil
        keyboardLocked = false
        closeOverlay()
    }

    // MARK: Tela

    func blackScreen() {
        showOverlay(black: true) { ScreenCleanView() }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    // MARK: Janelas

    private func showOverlay<V: View>(black: Bool = false, @ViewBuilder _ content: () -> V) {
        closeOverlay()
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = black
            w.backgroundColor = black ? .black : .clear
            w.isReleasedWhenClosed = false
            w.onExit = black ? { [weak self] in self?.closeOverlay() } : nil
            // Conteúdo só na tela principal; nas outras, só o fundo
            if screen == NSScreen.main {
                w.contentView = NSHostingView(rootView: content())
            } else if !black {
                w.contentView = NSHostingView(rootView: Color.black.opacity(0.55))
            }
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func closeOverlay() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

final class OverlayWindow: NSWindow {
    var onExit: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onExit { onExit() } else { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2, let onExit { onExit() } else { super.mouseDown(with: event) }
    }
}

struct KeyboardLockView: View {
    @ObservedObject var controller: CleaningController

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Theme.brand).frame(width: 96, height: 96)
                        .shadow(color: Theme.violet.opacity(0.5), radius: 24)
                    Image(systemName: "keyboard.badge.ellipsis").font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    Text(L("Teclado bloqueado")).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(L("Pode limpar à vontade. Nenhuma tecla vai funcionar."))
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                }
                Button { controller.unlockKeyboard() } label: {
                    Label(L("Desbloquear"), systemImage: "lock.open.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.brand))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Text(L("Destrava sozinho em %@", "\(controller.secondsLeft / 60):\(String(format: "%02d", controller.secondsLeft % 60))"))
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(44)
            .background(RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial))
            .environment(\.colorScheme, .dark)
        }
        .ignoresSafeArea()
    }
}

struct ScreenCleanView: View {
    @State private var showHint = true
    var body: some View {
        ZStack {
            Color.black
            if showHint {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 28))
                    Text(L("Tela de limpeza")).font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(L("Clique duas vezes ou aperte esc para sair")).font(.system(size: 13))
                }
                .foregroundStyle(.white.opacity(0.55))
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation(.easeOut(duration: 0.8)) { showHint = false } }
        }
    }
}
