import AppIntents
import AppKit

/// Filtro de Foco: em Ajustes do Sistema → Foco → (um Foco) → Filtros de Foco → Menew, a pessoa escolhe o que muda
/// enquanto aquele Foco estiver ligado. Quando o Foco desliga, o macOS chama de novo com tudo desligado e o Menew
/// desfaz só o que ele mesmo mudou.
struct MenewFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Menew Focus Filter"
    static let description: IntentDescription? = IntentDescription("Choose what Menew does while this Focus is on.")

    @Parameter(title: "Pause Clipboard History", default: false) var pauseClipboard: Bool
    @Parameter(title: "Only Meetings in the Notch", default: false) var quietNotch: Bool
    @Parameter(title: "Presentation Mode", default: false) var presentation: Bool
    @Parameter(title: "Mute Microphone", default: false) var muteMic: Bool
    @Parameter(title: "Work Profile") var profile: ProfileEntity?

    var displayRepresentation: DisplayRepresentation {
        var on: [String] = []
        if pauseClipboard { on.append(String(localized: "Pause Clipboard History")) }
        if quietNotch { on.append(String(localized: "Only Meetings in the Notch")) }
        if presentation { on.append(String(localized: "Presentation Mode")) }
        if muteMic { on.append(String(localized: "Mute Microphone")) }
        if let profile { on.append(profile.name) }
        return DisplayRepresentation(title: "Menew", subtitle: on.isEmpty ? nil : "\(on.joined(separator: ", "))")
    }

    @MainActor func perform() async throws -> some IntentResult {
        FocusFilterState.shared.apply(pauseClipboard: pauseClipboard, quietNotch: quietNotch, presentation: presentation,
                                      muteMic: muteMic, profile: profile?.id)
        return .result()
    }
}

/// Lembra o que o filtro mudou, para desfazer só isso quando o Foco desligar
@MainActor
final class FocusFilterState {
    static let shared = FocusFilterState()
    private let d = UserDefaults.standard
    /// Lido pelo notch: com o Foco, só reunião e gravação aparecem
    private(set) var quietNotch = false

    func apply(pauseClipboard: Bool, quietNotch: Bool, presentation: Bool, muteMic: Bool, profile: UUID?) {
        let app = NSApp.delegate as? AppDelegate
        // Clipboard: pausa e lembra; ao sair, retoma só se fomos nós que pausamos
        if pauseClipboard, !d.bool(forKey: "paused") {
            d.set(true, forKey: "paused"); d.set(true, forKey: "focus.pausedClipboard")
        } else if !pauseClipboard, d.bool(forKey: "focus.pausedClipboard") {
            d.set(false, forKey: "paused"); d.set(false, forKey: "focus.pausedClipboard")
        }
        self.quietNotch = quietNotch
        NotchCenter.shared.update()
        if presentation, !PresentationMode.shared.isOn {
            PresentationMode.shared.set(true); d.set(true, forKey: "focus.presentation")
        } else if !presentation, d.bool(forKey: "focus.presentation") {
            PresentationMode.shared.set(false); d.set(false, forKey: "focus.presentation")
        }
        if let tb = app?.toolbox {
            if muteMic, !tb.micMuted {
                _ = tb.toggleMic(); d.set(true, forKey: "focus.mutedMic")
            } else if !muteMic, d.bool(forKey: "focus.mutedMic") {
                if tb.micMuted { _ = tb.toggleMic() }
                d.set(false, forKey: "focus.mutedMic")
            }
            // O perfil só é ativado ao ligar o Foco (abrir apps e arrumar janelas não tem como desfazer)
            if let profile, let p = ProfileStore.shared.profile(profile) { ProfileStore.shared.activate(p, toolbox: tb) }
        }
    }
}
