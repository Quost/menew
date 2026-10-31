import AppIntents
import AppKit

// Ações do Menew na Siri, no app Atalhos e no Spotlight. Rodam dentro do Menew (que precisa estar aberto ou é aberto
// pelo sistema) e usam as mesmas funções dos botões. Títulos em inglês; as traduções ficam em Resources/*.lproj/Localizable.strings.

@MainActor
private var app: AppDelegate? { NSApp.delegate as? AppDelegate }

struct KeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Keeps the screen on and the Mac from sleeping, for a while or until you turn it off.")

    @Parameter(title: "Turn On", default: true) var on: Bool
    @Parameter(title: "Minutes") var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Keep awake \(\.$on) for \(\.$minutes) minutes")
    }

    @MainActor func perform() async throws -> some IntentResult {
        app?.toolbox.setKeepAwake(on, minutes: on ? minutes : nil)
        return .result()
    }
}

struct MuteMicrophoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute Microphone"
    static let description = IntentDescription("Mutes or unmutes the microphone in every app.")

    @Parameter(title: "Muted", default: true) var muted: Bool

    @MainActor func perform() async throws -> some IntentResult {
        if let tb = app?.toolbox, tb.micMuted != muted { tb.toggleMic() }
        return .result()
    }
}

struct PresentationModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Presentation Mode"
    static let description = IntentDescription("Hides desktop icons, keeps the Mac awake, pauses the clipboard and shows only the icon in the menu bar.")

    @Parameter(title: "Turn On", default: true) var on: Bool

    @MainActor func perform() async throws -> some IntentResult {
        PresentationMode.shared.set(on)
        return .result()
    }
}

struct DarkModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Dark Mode"
    static let description = IntentDescription("Switches macOS between light and dark appearance.")

    @Parameter(title: "Dark", default: true) var dark: Bool

    @MainActor func perform() async throws -> some IntentResult {
        if let tb = app?.toolbox, tb.darkMode != dark { tb.toggleDarkMode() }
        return .result()
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Timer"
    static let description = IntentDescription("Starts a focus session with a countdown in the menu bar.")

    @Parameter(title: "Minutes", default: 25) var minutes: Int

    @MainActor func perform() async throws -> some IntentResult {
        FocusTimer.shared.start(minutes: max(1, minutes))
        return .result()
    }
}

struct CaptureScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Screen"
    static let description = IntentDescription("Select an area or window and annotate the screenshot.")

    @MainActor func perform() async throws -> some IntentResult {
        ScreenCapture.area()
        return .result()
    }
}

struct CopyTextFromScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Text from Screen"
    static let description = IntentDescription("Select an area of the screen and copy the text in it, recognized on your Mac.")

    @MainActor func perform() async throws -> some IntentResult {
        TextRecognizer.captureScreenText()
        return .result()
    }
}

struct OpenClipboardHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Clipboard History"

    @MainActor func perform() async throws -> some IntentResult {
        app?.clipPanel.show()
        return .result()
    }
}

struct OpenCommandPaletteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Command Palette"

    @MainActor func perform() async throws -> some IntentResult {
        app?.palette.show()
        return .result()
    }
}

struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note"
    static let description = IntentDescription("Creates a note in Menew. The first line is the title.")

    @Parameter(title: "Text") var text: String

    @MainActor func perform() async throws -> some IntentResult {
        _ = app?.notes.create(text: text)
        HUD.show(icon: "note.text", color: .yellow, text: L("Nota criada"))
        return .result()
    }
}

// MARK: Perfis

struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Work Profile"
    static let defaultQuery = ProfileQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProfileQuery: EntityQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        ProfileStore.shared.profiles.filter { identifiers.contains($0.id) }.map { ProfileEntity(id: $0.id, name: $0.name) }
    }

    @MainActor func suggestedEntities() async throws -> [ProfileEntity] {
        ProfileStore.shared.profiles.map { ProfileEntity(id: $0.id, name: $0.name) }
    }
}

struct ActivateProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Activate Work Profile"
    static let description = IntentDescription("Opens the profile's apps, arranges its windows and applies its settings.")

    @Parameter(title: "Profile") var profile: ProfileEntity

    @MainActor func perform() async throws -> some IntentResult {
        if let p = ProfileStore.shared.profile(profile.id), let tb = app?.toolbox { ProfileStore.shared.activate(p, toolbox: tb) }
        return .result()
    }
}

// MARK: Frases da Siri e do Spotlight

struct MenewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureScreenIntent(), phrases: ["Capture the screen with \(.applicationName)"],
                    shortTitle: "Capture Screen", systemImageName: "camera.viewfinder")
        AppShortcut(intent: CopyTextFromScreenIntent(), phrases: ["Copy text from screen with \(.applicationName)"],
                    shortTitle: "Copy Text from Screen", systemImageName: "text.viewfinder")
        AppShortcut(intent: MuteMicrophoneIntent(), phrases: ["Mute my microphone with \(.applicationName)"],
                    shortTitle: "Mute Microphone", systemImageName: "mic.slash.fill")
        AppShortcut(intent: KeepAwakeIntent(), phrases: ["Keep my Mac awake with \(.applicationName)"],
                    shortTitle: "Keep Mac Awake", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: PresentationModeIntent(), phrases: ["Start presentation mode in \(.applicationName)"],
                    shortTitle: "Presentation Mode", systemImageName: "play.rectangle.fill")
        AppShortcut(intent: StartFocusIntent(), phrases: ["Start a focus session in \(.applicationName)"],
                    shortTitle: "Start Focus Timer", systemImageName: "timer")
        AppShortcut(intent: ActivateProfileIntent(), phrases: ["Activate \(\.$profile) in \(.applicationName)",
                                                               "Activate a work profile in \(.applicationName)"],
                    shortTitle: "Activate Work Profile", systemImageName: "square.stack.3d.up.fill")
        AppShortcut(intent: OpenClipboardHistoryIntent(), phrases: ["Open clipboard history in \(.applicationName)"],
                    shortTitle: "Clipboard History", systemImageName: "doc.on.clipboard")
        AppShortcut(intent: NewNoteIntent(), phrases: ["Create a note in \(.applicationName)"],
                    shortTitle: "New Note", systemImageName: "note.text")
    }
}
