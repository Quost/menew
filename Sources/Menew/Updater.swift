import AppKit
import Sparkle

/// Atualização automática via Sparkle (feed nas releases do GitHub, assinado com EdDSA).
/// A verificação diária não abre janela sozinha: o Menew mostra um aviso discreto no menu,
/// e a janela de atualização só aparece quando você clica nele.
@MainActor
final class UpdaterModel: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    /// Versão nova encontrada pela verificação automática e ainda não vista
    @Published private(set) var pendingVersion: String?
    var onPendingChange: (() -> Void)?
    private var reminderVersion: String?   // achada pela verificação, ainda não mostrada
    private var downloadedVersion: String? // baixada em silêncio, instala ao sair
    private var downloadedNotes: String?
    private var installNow: (() -> Void)?

    /// O modo captura de tela não inicia o Sparkle
    init(enabled: Bool) {
        super.init()
        if enabled {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        }
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    /// Clique no ícone com o pontinho. A versão já baixada fica presa à sessão do Sparkle,
    /// então a janela de instalar é nossa; a só encontrada abre a janela do Sparkle.
    /// A janela de instalar aberta agora: outro clique no ícone só a traz para a frente (não abre outra por cima)
    private var installAlert: NSAlert?

    func showPendingUpdate() {
        guard let version = downloadedVersion, let install = installNow else { return checkForUpdates() }
        NSApp.activate(ignoringOtherApps: true)
        if let open = installAlert { open.window.makeKeyAndOrderFront(nil); return }
        let alert = NSAlert()
        alert.messageText = L("Menew %@ está pronto para instalar", version)
        if let notes = downloadedNotes, !notes.isEmpty { alert.accessoryView = Self.notesView(notes) }
        alert.addButton(withTitle: L("Instalar e reabrir"))
        alert.addButton(withTitle: L("Depois"))
        installAlert = alert
        let answer = alert.runModal()
        installAlert = nil
        if answer == .alertFirstButtonReturn {
            install()
        } else { // instala sozinha quando o Menew fechar
            downloadedVersion = nil
            updatePending()
        }
    }

    /// As notas numa caixa com rolagem: versões grandes não esticam a janela além da tela
    static func notesView(_ notes: String, width: CGFloat = 420, maxHeight: CGFloat = 320) -> NSView {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 4, height: 6)
        text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        text.textColor = .labelColor
        text.string = notes
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        let used = text.layoutManager?.usedRect(for: text.textContainer!).height ?? maxHeight
        let height = min(maxHeight, ceil(used) + 14)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = text
        text.frame.size.width = scroll.contentSize.width
        return scroll
    }

    /// Notas da versão (HTML do appcast) em texto simples
    private nonisolated static func plainNotes(_ item: SUAppcastItem) -> String? {
        guard let html = item.itemDescription, let data = html.data(using: .utf8),
              let text = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                       .characterEncoding: String.Encoding.utf8.rawValue],
                                                 documentAttributes: nil).string
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updatePending() {
        let v = reminderVersion ?? downloadedVersion
        guard v != pendingVersion else { return }
        pendingVersion = v
        onPendingChange?()
    }

    // MARK: Download automático

    /// Com "baixar e instalar automaticamente", a versão nova fica pronta para quando o app fechar.
    /// App de barra de menus quase nunca fecha, então avisa com o pontinho; o clique abre a janela de instalar.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString, notes = Self.plainNotes(item)
        MainActor.assumeIsolated {
            downloadedVersion = version
            downloadedNotes = notes
            installNow = immediateInstallHandler
            updatePending()
        }
        return true
    }

    // MARK: Lembretes discretos (Sparkle "gentle reminders")

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Verificação automática nunca abre janela: o clique no ícone abre
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            if !handleShowingUpdate && !state.userInitiated { reminderVersion = version; updatePending() }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { reminderVersion = nil; updatePending() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { reminderVersion = nil; updatePending() }
    }
}
