import AppKit
import Carbon.HIToolbox

/// Expansor de texto: digitar a abreviação de um snippet (ex.: ";email") troca pelo texto dele.
/// Desligado por padrão. Só escuta o teclado enquanto está ligado e existe alguma abreviação;
/// para em campos de senha (Secure Input) e nos apps ignorados pelo clipboard.
@MainActor
final class TextExpander {
    static let shared = TextExpander()
    static let key = "textExpander"

    private weak var clipboard: ClipboardManager?
    private var monitor: Any?
    private var mouseMonitor: Any?
    private var buffer = ""
    private var expanding = false

    func start(clipboard: ClipboardManager) {
        self.clipboard = clipboard
        refresh()
    }

    /// Liga ou desliga a escuta conforme o ajuste e as abreviações existentes
    func refresh() {
        let wanted = UserDefaults.standard.bool(forKey: Self.key) && Module.clipboard.isOn
            && !abbreviations().isEmpty && AXIsProcessTrusted()
        if wanted, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
                MainActor.assumeIsolated { self?.handle(e) }
            }
            // clicar move o cursor: o que foi digitado antes não conta mais
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                MainActor.assumeIsolated { self?.buffer = "" }
            }
        } else if !wanted, let m = monitor {
            NSEvent.removeMonitor(m)
            if let mm = mouseMonitor { NSEvent.removeMonitor(mm) }
            monitor = nil
            mouseMonitor = nil
            buffer = ""
        }
    }

    private func abbreviations() -> [Snippet] {
        (clipboard?.snippets.snippets ?? []).filter { ($0.abbreviation ?? "").count >= 2 }
    }

    private func handle(_ e: NSEvent) {
        guard !expanding else { return }
        if IsSecureEventInputEnabled() { buffer = ""; return }
        if !e.modifierFlags.intersection([.command, .control]).isEmpty { buffer = ""; return }
        switch Int(e.keyCode) {
        case kVK_Delete:
            if !buffer.isEmpty { buffer.removeLast() }
            return
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape,
             kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
            buffer = ""
            return
        default: break
        }
        guard let chars = e.characters, !chars.isEmpty else { return }
        buffer = String((buffer + chars).suffix(40))

        for s in abbreviations() {
            guard let abbr = s.abbreviation, buffer.hasSuffix(abbr) else { continue }
            // "addr" não dispara no meio de "address": antes da abreviação precisa vir início, espaço ou pontuação
            let before = buffer.dropLast(abbr.count).last
            if let before, before.isLetter || before.isNumber, abbr.first?.isLetter == true { continue }
            if let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               clipboard?.ignoredApps.contains(bundle) == true { return }
            expand(s, erasing: abbr.count)
            return
        }
    }

    /// Apaga a abreviação, cola o texto e devolve o clipboard como estava, sem nada entrar no histórico
    private func expand(_ s: Snippet, erasing count: Int) {
        guard let clipboard else { return }
        expanding = true
        buffer = ""
        let text = SnippetStore.expand(s.text)
        let pb = NSPasteboard.general
        let saved = (pb.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { d, t in d[t] = item.data(forType: t) }
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<count {
            CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Delete), keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Delete), keyDown: false)?.post(tap: .cghidEventTap)
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        clipboard.ignoreCurrentChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ClipboardManager.postCommandV()
            // tempo para o app ler o ⌘V antes de devolver o conteúdo anterior
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                pb.clearContents()
                pb.writeObjects(saved.map { dict in
                    let item = NSPasteboardItem()
                    for (t, d) in dict { item.setData(d, forType: t) }
                    return item
                })
                clipboard.ignoreCurrentChange()
                self.expanding = false
            }
        }
    }
}
