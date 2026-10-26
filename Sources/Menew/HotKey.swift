import AppKit
import Carbon
import SwiftUI

/// Atalho global via Carbon: não precisa de permissão de Acessibilidade.
final class HotKey {
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var installed = false

    private var ref: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping () -> Void) {
        Self.installHandlerOnce()
        Self.handlers[id] = handler
        let hkID = EventHotKeyID(signature: OSType(0x4D4D4E55), id: id) // 'MMNU'
        RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }

    private static func installHandlerOnce() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

// MARK: Atalhos configuráveis

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // máscara do Carbon (cmdKey, shiftKey…)
    var key: String         // como mostrar a tecla: "V", "Espaço", "F5"

    static let clipboardDefault = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), key: "V")
    static let menuDefault = Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | optionKey), key: "M")

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// nil quando não há ⌘, ⌥ ou ⌃ (um atalho global só com letra atrapalharia a digitação)
    init?(event: NSEvent) {
        let f = event.modifierFlags
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        guard m != 0 else { return nil }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        keyCode = UInt32(event.keyCode)
        modifiers = m
        key = Self.name(for: event)
    }

    private static func name(for e: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let s = special[Int(e.keyCode)] { return s }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }

    // Persistência em UserDefaults
    static func load(_ name: String, default def: Shortcut) -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: name),
              let s = try? JSONDecoder().decode(Shortcut.self, from: data) else { return def }
        return s
    }

    func save(_ name: String) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: name) }
    }
}

/// Registra os atalhos globais e permite pausá-los enquanto o usuário grava um novo
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    static let clipboardKey = "shortcutClipboard"
    static let menuKey = "shortcutMenu"

    var onClipboard: (() -> Void)?
    var onMenu: (() -> Void)?
    private var hotKeys: [HotKey] = []

    func register() {
        hotKeys = []   // libera os anteriores
        let clip = Shortcut.load(Self.clipboardKey, default: .clipboardDefault)
        let menu = Shortcut.load(Self.menuKey, default: .menuDefault)
        hotKeys = [
            HotKey(keyCode: clip.keyCode, modifiers: clip.modifiers, id: 1) { [weak self] in
                MainActor.assumeIsolated { self?.onClipboard?() }
            },
            HotKey(keyCode: menu.keyCode, modifiers: menu.modifiers, id: 2) { [weak self] in
                MainActor.assumeIsolated { self?.onMenu?() }
            },
        ]
    }

    func suspend() { hotKeys = [] }
}

/// Campo que grava um atalho: clique, pressione a combinação; esc cancela
struct ShortcutRecorder: View {
    let name: String
    let fallback: Shortcut
    @State private var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    init(name: String, fallback: Shortcut) {
        self.name = name
        self.fallback = fallback
        _shortcut = State(initialValue: Shortcut.load(name, default: fallback))
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { recording ? stop() : start() } label: {
                Text(recording ? L("Pressione o atalho…") : shortcut.display)
                    .font(.system(size: 12, weight: .medium, design: recording ? .default : .rounded))
                    .frame(minWidth: 90)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: recording ? 1.5 : 0.5))
            }
            .buttonStyle(.plain)
            if shortcut != fallback && !recording {
                Button { apply(fallback) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(L("Voltar ao padrão"))
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let e = event
            MainActor.assumeIsolated {
                if e.keyCode == UInt16(kVK_Escape) { stop(); return }
                if let s = Shortcut(event: e) { apply(s) } else { NSSound.beep() }
            }
            return nil
        }
    }

    private func apply(_ s: Shortcut) {
        shortcut = s
        s.save(name)
        stop()
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyCenter.shared.register()
    }
}
