import AppKit
import SwiftUI

struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
}

/// Textos prontos. Aparecem no ⌘⇧V pelo filtro "Snippets" e nunca entram no histórico.
@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []
    private let url: URL?

    init(dir: URL?) {
        url = dir?.appendingPathComponent("snippets.json")
        if let url, let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = list
        } else {
            // Exemplos na primeira vez, para mostrar como funciona
            snippets = [
                Snippet(title: L("Data de hoje"), text: "{date}"),
                Snippet(title: L("Assinatura de e-mail"), text: L("Abraços,\nSeu nome")),
            ]
            if url != nil { save() }
        }
    }

    func upsert(_ s: Snippet) {
        if let i = snippets.firstIndex(where: { $0.id == s.id }) { snippets[i] = s } else { snippets.insert(s, at: 0) }
        save()
    }

    func delete(_ s: Snippet) {
        snippets.removeAll { $0.id == s.id }
        save()
    }

    /// Snippets como itens da lista do ⌘⇧V
    func items(matching query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return snippets
            .filter { q.isEmpty || "\($0.title) \($0.text)".range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .map { ClipItem(id: $0.id, kind: .text, text: $0.text, snippetTitle: $0.title) }
    }

    /// {date}, {time} e {clipboard} são preenchidos na hora de colar
    static func expand(_ text: String) -> String {
        let now = Date()
        var out = text
        out = out.replacingOccurrences(of: "{date}", with: now.formatted(.dateTime.day().month().year().locale(L10n.locale)))
        out = out.replacingOccurrences(of: "{time}", with: now.formatted(.dateTime.hour().minute().locale(L10n.locale)))
        if out.contains("{clipboard}") {
            out = out.replacingOccurrences(of: "{clipboard}", with: NSPasteboard.general.string(forType: .string) ?? "")
        }
        return out
    }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Lista e edição de snippets, dentro da aba Clipboard do menu
struct SnippetsView: View {
    @ObservedObject var store: SnippetStore
    @State private var editing: Snippet?
    @State private var isNew = false

    var body: some View {
        VStack(spacing: 10) {
            if let snippet = editing {
                SnippetEditor(snippet: snippet, isNew: isNew,
                              onSave: { store.upsert($0); editing = nil },
                              onCancel: { editing = nil })
            } else {
                HStack {
                    Text(L("Cole com ⌘⇧V → Snippets")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    PillButton(title: L("Novo snippet"), icon: "plus", primary: true) {
                        isNew = true
                        editing = Snippet(title: "", text: "")
                    }
                }
                if store.snippets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.badge.star").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
                        Text(L("Nenhum snippet ainda")).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(store.snippets) { s in
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.purple.gradient)
                                        Image(systemName: "text.badge.star").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                    }
                                    .frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                        Text(s.text.split(whereSeparator: \.isNewline).joined(separator: " "))
                                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    IconButton(icon: "pencil", help: L("Editar")) { isNew = false; editing = s }
                                    IconButton(icon: "trash", help: L("Apagar")) { store.delete(s) }
                                }
                                .card(padding: 8)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }
}

private struct SnippetEditor: View {
    @State var snippet: Snippet
    let isNew: Bool
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isNew ? L("Novo snippet") : L("Editar snippet")).font(.system(size: 13, weight: .semibold))
            TextField(L("Título"), text: $snippet.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .glassField()
            TextEditor(text: $snippet.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .glass(cornerRadius: 14)
            Text(L("Use {date}, {time} e {clipboard} para preencher na hora de colar."))
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                PillButton(title: L("Cancelar"), action: onCancel)
                PillButton(title: L("Salvar"), icon: "checkmark", primary: true) {
                    var s = snippet
                    if s.title.trimmingCharacters(in: .whitespaces).isEmpty {
                        s.title = String(s.text.split(whereSeparator: \.isNewline).first ?? "Snippet")
                    }
                    onSave(s)
                }
                .disabled(snippet.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(snippet.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
