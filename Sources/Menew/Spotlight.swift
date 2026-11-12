import AppIntents
import AppKit
import Combine
import CoreSpotlight
import UniformTypeIdentifiers

/// Notas do Menew no Spotlight: o título e o texto entram no índice do próprio Mac, e escolher o resultado abre a nota.
/// Notas protegidas e de senhas nunca entram. Desligado em Ajustes → Privacidade, o índice é apagado.
@MainActor
final class SpotlightNotes {
    static let shared = SpotlightNotes()
    static let key = "spotlightNotes"
    static let domain = "com.matheusquost.menew.notes"
    private var bag: AnyCancellable?

    var isOn: Bool { UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true }

    func start(_ store: NotesStore) {
        // Reindexa alguns segundos depois de parar de digitar
        bag = store.$notes.debounce(for: .seconds(3), scheduler: RunLoop.main).sink { notes in
            MainActor.assumeIsolated { SpotlightNotes.shared.index(notes) }
        }
    }

    func setOn(_ on: Bool, store: NotesStore) {
        UserDefaults.standard.set(on, forKey: Self.key)
        index(store.notes)
    }

    func index(_ notes: [Note]) {
        // Modo demo: nem indexa as notas fictícias, nem apaga o índice real
        guard !DemoMode.isOn else { return }
        let index = CSSearchableIndex.default()
        guard isOn else { index.deleteSearchableItems(withDomainIdentifiers: [Self.domain]); return }
        let items = notes.filter { !$0.secure && !$0.isPasswords }.map { n -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = n.title
            a.contentDescription = n.preview
            a.textContent = n.text
            a.keywords = n.tags + ["Menew"]
            a.contentModificationDate = n.updated
            let item = CSSearchableItem(uniqueIdentifier: "note:\(n.id.uuidString)", domainIdentifier: Self.domain, attributeSet: a)
            item.expirationDate = .distantFuture
            return item
        }
        // Troca tudo de uma vez: some do Spotlight o que foi apagado ou protegido
        index.deleteSearchableItems(withDomainIdentifiers: [Self.domain]) { _ in
            index.indexSearchableItems(items)
        }
    }

    /// O id da nota de um resultado do Spotlight
    static func noteID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, id.hasPrefix("note:") else { return nil }
        return UUID(uuidString: String(id.dropFirst(5)))
    }
}

// MARK: Siri

@MainActor
private var app: AppDelegate? { NSApp.delegate as? AppDelegate }

/// "Como está meu Mac no Menew?": a Siri responde em uma frase
struct SystemStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Mac Status"
    static let description = IntentDescription("Tells you CPU, memory, free disk space and battery in one sentence.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let m = app?.monitor else { return .result(value: "", dialog: "") }
        let mem = m.memTotal == 0 ? 0 : Int((Double(m.memUsed) / Double(m.memTotal) * 100).rounded())
        var text = L("CPU em %@, memória em %@, %@ livres no disco", "\(Int((m.cpu * 100).rounded()))%", "\(mem)%",
                     ByteCountFormatter.string(fromByteCount: m.diskFree, countStyle: .file))
        if let b = m.battery { text += L(" e bateria em %@", "\(b.percent)%") }
        text += "."
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct NoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static let defaultQuery = NoteQuery()
    let id: UUID
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct NoteQuery: EntityStringQuery {
    @MainActor private var list: [NoteEntity] {
        (app?.notes.notes ?? []).filter { !$0.isPasswords }.map { NoteEntity(id: $0.id, title: $0.title) }
    }
    @MainActor func entities(for identifiers: [UUID]) async throws -> [NoteEntity] { list.filter { identifiers.contains($0.id) } }
    @MainActor func entities(matching string: String) async throws -> [NoteEntity] {
        let q = PaletteSearch.fold(string)
        return list.filter { PaletteSearch.fold($0.title).contains(q) }
    }
    @MainActor func suggestedEntities() async throws -> [NoteEntity] { Array(list.prefix(20)) }
}

struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Note"
    static let description = IntentDescription("Opens one of your Menew notes.")

    @Parameter(title: "Note") var note: NoteEntity

    @MainActor func perform() async throws -> some IntentResult {
        app?.openNote(note.id)
        return .result()
    }
}
