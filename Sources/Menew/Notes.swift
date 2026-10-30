import AppKit
import LocalAuthentication
import Security
import SwiftUI

// MARK: Modelo

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Notas protegidas guardam aqui só a primeira linha (título); o resto fica nas Chaves do macOS
    var text: String
    var secure = false
    var created = Date()
    var updated = Date()
    /// nil é texto (Markdown); opcional para as notas salvas antes continuarem abrindo
    var kind: Kind? = nil

    enum Kind: String, Codable, CaseIterable {
        case text, passwords
        var title: String { self == .text ? L("Texto") : L("Senhas") }
        var icon: String { self == .text ? "note.text" : "key.fill" }
    }

    var isPasswords: Bool { kind == .passwords }

    var title: String {
        let line = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let clean = line.drop { $0 == "#" || $0 == " " }.trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? L("Nota sem título") : String(clean.prefix(80))
    }

    /// Segunda linha com conteúdo, sem marcações de Markdown
    var preview: String {
        guard !secure else { return L("Conteúdo protegido") }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var rest = lines.dropFirst().first ?? ""
        // Tira marcadores de bloco (título, citação, lista, tarefa) e de ênfase
        rest = rest.replacingOccurrences(of: #"^(#+\s*|>\s*|[-*+]\s+(\[[ xX]\]\s*)?|\d+[.)]\s+)"#, with: "", options: .regularExpression)
        rest = rest.replacingOccurrences(of: #"[*_`~]"#, with: "", options: .regularExpression)
        return String(rest.prefix(120))
    }

    var tags: [String] { secure ? [] : Note.tags(in: text) }

    /// #tag em qualquer lugar do texto ("# Título", com espaço, não conta)
    static func tags(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"(?:^|\s)#([\p{L}\p{N}_-]+)"#) else { return [] }
        let ns = text as NSString
        var seen: [String] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: m.range(at: 1)).lowercased()
            if !seen.contains(t) { seen.append(t) }
        }
        return seen
    }
}

/// Linha "chave: valor" de uma nota de senhas. O texto da nota continua sendo o título na primeira linha
/// e um campo por linha, então trocar de tipo não perde nada.
struct SecretField: Identifiable, Equatable {
    var id = UUID()
    var key: String
    var value: String

    static func parse(_ text: String) -> (title: String, fields: [SecretField]) {
        var lines = text.components(separatedBy: "\n")
        let title = lines.isEmpty ? "" : lines.removeFirst()
        let fields = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { line -> SecretField in
            guard let colon = line.firstIndex(of: ":") else { return SecretField(key: line.trimmingCharacters(in: .whitespaces), value: "") }
            var value = line[line.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
            return SecretField(key: line[..<colon].trimmingCharacters(in: .whitespaces), value: String(value))
        }
        return (title, fields)
    }

    static func format(title: String, fields: [SecretField]) -> String {
        let flat = { (s: String) in s.replacingOccurrences(of: "\n", with: " ") }
        let rows = fields.map { f in
            let key = flat(f.key).replacingOccurrences(of: ":", with: "")
            return f.value.isEmpty ? "\(key):" : "\(key): \(flat(f.value))"
        }
        return ([flat(title)] + rows).joined(separator: "\n")
    }
}

/// Copia um segredo marcado como confidencial: o Menew e outros gerenciadores de clipboard não guardam,
/// e some do clipboard depois de 30 s se nada mais foi copiado
@MainActor
enum SecretCopy {
    static func copy(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let count = pb.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if pb.changeCount == count { pb.clearContents() }
        }
        HUD.show(icon: "key.fill", color: .blue, text: L("Copiado · some em 30 s"), duration: 1.4)
    }
}

/// Conteúdo das notas protegidas nas Chaves do macOS (criptografado pelo sistema)
enum NoteVault {
    private static let service = "com.matheusquost.menew.notes"

    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    static func read(_ id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ text: String, id: UUID) {
        let data = Data(text.utf8)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(id)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    static func delete(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}

// MARK: Armazenamento

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    /// Notas protegidas abertas nesta sessão (fecham quando o menu fecha)
    @Published private(set) var unlocked: [UUID: String] = [:]
    /// Touch ID na tela: o menu não fecha enquanto isso (o pedido do sistema tira o foco dele)
    private(set) var authenticating = false

    private let url: URL?
    private var saveWork: DispatchWorkItem?

    init(dir: URL?) {
        url = dir?.appendingPathComponent("notes.json")
        if let url, let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Note].self, from: data) {
            notes = list
        } else if let dir, let old = try? String(contentsOf: dir.appendingPathComponent("notas.md"), encoding: .utf8),
                  !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Versões anteriores tinham uma nota só, em notas.md
            notes = [Note(text: old)]
            save()
        }
    }

    /// Notas de exemplo para as capturas de tela
    static func demo() -> NotesStore {
        let s = NotesStore(dir: nil)
        let pt = L10n.current == .pt
        s.notes = pt ? [
            Note(text: "# Ideias pro Menew\n- [x] Snippets\n- [ ] Atalhos por app\n- [ ] Widget de clima\n\n#ideias #menew", updated: Date().addingTimeInterval(-600)),
            Note(text: "Reunião de sexta\n**Pauta:** orçamento e prazos\n> Levar os números do trimestre\n\n#trabalho", updated: Date().addingTimeInterval(-7200)),
            Note(text: "Wi-Fi de casa", secure: true, updated: Date().addingTimeInterval(-86400), kind: .passwords),
            Note(text: "Lista de compras\n- café\n- pão\n- queijo\n\n#casa", updated: Date().addingTimeInterval(-172800)),
        ] : [
            Note(text: "# Menew ideas\n- [x] Snippets\n- [ ] Per-app shortcuts\n- [ ] Weather widget\n\n#ideas #menew", updated: Date().addingTimeInterval(-600)),
            Note(text: "Friday meeting\n**Agenda:** budget and deadlines\n> Bring the quarterly numbers\n\n#work", updated: Date().addingTimeInterval(-7200)),
            Note(text: "Home Wi-Fi", secure: true, updated: Date().addingTimeInterval(-86400), kind: .passwords),
            Note(text: "Groceries\n- coffee\n- bread\n- cheese\n\n#home", updated: Date().addingTimeInterval(-172800)),
        ]
        if let wifi = s.notes.first(where: \.isPasswords) {
            s.unlocked[wifi.id] = SecretField.format(title: wifi.text, fields: [
                SecretField(key: L("Rede"), value: "Casa-5G"), SecretField(key: L("Senha"), value: "correct-horse-battery"),
                SecretField(key: L("Roteador"), value: "http://192.168.0.1"), SecretField(key: "PIN", value: "4821"),
            ])
        }
        return s
    }

    var allTags: [String] {
        var seen: [String] = []
        for n in notes { for t in n.tags where !seen.contains(t) { seen.append(t) } }
        return seen.sorted()
    }

    func filtered(query: String, tag: String?) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return notes
            .filter { tag == nil || $0.tags.contains(tag!) }
            .filter { q.isEmpty || $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { $0.updated > $1.updated }
    }

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    /// Texto completo: das protegidas, só depois de desbloquear
    func text(of id: UUID) -> String {
        guard let n = note(id) else { return "" }
        return n.secure ? (unlocked[id] ?? "") : n.text
    }

    func isLocked(_ id: UUID) -> Bool { note(id)?.secure == true && unlocked[id] == nil }

    func create(text: String = "") -> UUID {
        let n = Note(text: text)
        notes.insert(n, at: 0)
        save()
        return n.id
    }

    func setText(_ text: String, of id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[i].secure {
            guard unlocked[id] != nil else { return }
            unlocked[id] = text
            NoteVault.write(text, id: id)
            notes[i].text = Self.firstLine(text)
        } else {
            notes[i].text = text
        }
        notes[i].updated = Date()
        scheduleSave()
    }

    /// Nota de senhas nova: já protegida, com usuário e senha para preencher
    func createPasswords() -> UUID {
        let id = create(text: SecretField.format(title: "", fields: [SecretField(key: L("Usuário"), value: ""), SecretField(key: L("Senha"), value: "")]))
        setKind(.passwords, for: id)
        return id
    }

    /// Senhas ficam sempre protegidas; voltar para texto mantém a proteção
    func setKind(_ kind: Note.Kind, for id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].kind = kind == .text ? nil : kind
        if kind == .passwords, !notes[i].secure { setSecure(true, for: id) } else { save() }
    }

    /// Só a primeira linha fica fora das Chaves, mesmo vazia
    private static func firstLine(_ text: String) -> String {
        String(text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        unlocked[id] = nil
        NoteVault.delete(id)
        save()
    }

    /// Protege (texto vai para as Chaves) ou desprotege (volta para o arquivo de notas)
    func setSecure(_ secure: Bool, for id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].secure != secure else { return }
        if secure {
            let full = notes[i].text
            NoteVault.write(full, id: id)
            notes[i].secure = true
            notes[i].text = Self.firstLine(full)
            unlocked[id] = full
        } else {
            guard let full = unlocked[id] else { return }
            notes[i].secure = false
            notes[i].text = full
            NoteVault.delete(id)
            unlocked[id] = nil
        }
        save()
    }

    /// Touch ID ou senha do Mac
    func unlock(_ id: UUID) async -> Bool {
        if unlocked[id] != nil { return true }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        NSApp.activate(ignoringOtherApps: true)
        authenticating = true
        defer { authenticating = false }
        let ok = (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("abrir a nota protegida"))) ?? false
        guard ok else { return false }
        unlocked[id] = NoteVault.read(id) ?? note(id)?.text ?? ""
        return true
    }

    func lock(_ id: UUID) { unlocked[id] = nil }

    func lockAll() { unlocked = [:] }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.save() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
