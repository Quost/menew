import AppKit
import Sparkle

/// Atualização automática via Sparkle (feed nas releases do GitHub, assinado com EdDSA)
@MainActor
final class UpdaterModel: ObservableObject {
    private let controller: SPUStandardUpdaterController?

    /// O modo captura de tela não inicia o Sparkle
    init(enabled: Bool) {
        controller = enabled
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
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
}
