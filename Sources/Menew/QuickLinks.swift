import AppKit
import SwiftUI

/// Links rápidos na paleta: "jira ABC-123", "gh menew", "maps avenida paulista". Cada um é uma palavra e um endereço
/// com {q} no lugar do que você digitar. Abre no seu navegador; o Menew não acessa a internet para isso.
struct QuickLink: Codable, Identifiable, Equatable {
    var id = UUID()
    var keyword: String
    var name: String
    var url: String

    /// Endereço com o texto no lugar de {q}; sem {q}, o endereço é aberto como está
    func url(for text: String) -> URL? {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? text
        return URL(string: url.replacingOccurrences(of: "{q}", with: encoded))
    }

    var needsText: Bool { url.contains("{q}") }
}

@MainActor
final class QuickLinkStore: ObservableObject {
    static let shared = QuickLinkStore()
    static let key = "quickLinks"
    @Published private(set) var links: [QuickLink] = []

    static let defaults: [QuickLink] = [
        QuickLink(keyword: "g", name: "Google", url: "https://www.google.com/search?q={q}"),
        QuickLink(keyword: "ddg", name: "DuckDuckGo", url: "https://duckduckgo.com/?q={q}"),
        QuickLink(keyword: "yt", name: "YouTube", url: "https://www.youtube.com/results?search_query={q}"),
        QuickLink(keyword: "wiki", name: "Wikipedia", url: "https://wikipedia.org/w/index.php?search={q}"),
        QuickLink(keyword: "gh", name: "GitHub", url: "https://github.com/search?q={q}"),
        QuickLink(keyword: "maps", name: "Apple Maps", url: "https://maps.apple.com/?q={q}"),
    ]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let list = try? JSONDecoder().decode([QuickLink].self, from: data) {
            links = list
        } else {
            links = Self.defaults
        }
    }

    func add(_ link: QuickLink) {
        links.removeAll { $0.keyword.lowercased() == link.keyword.lowercased() }
        links.append(link)
        save()
    }

    func remove(_ link: QuickLink) {
        links.removeAll { $0.id == link.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(links) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// Itens da paleta para o texto como foi digitado (com maiúsculas: "jira ABC-123")
    func paletteItems(raw: String) -> [PaletteItem] {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        var out: [PaletteItem] = []
        let word = String(text.split(separator: " ", maxSplits: 1).first ?? "")
        let rest = text.dropFirst(word.count).trimmingCharacters(in: .whitespaces)

        for link in links where link.keyword.lowercased() == word.lowercased() {
            if link.needsText && rest.isEmpty {
                out.append(PaletteItem(id: "link.\(link.id)", kind: .calc, title: L("%@: digite o que buscar", link.name),
                                       subtitle: link.url, keywords: text, icon: .symbol("link", .blue), remember: false,
                                       keepOpen: true) {})
            } else if let url = link.url(for: rest) {
                out.append(PaletteItem(id: "link.\(link.id)", kind: .calc,
                                       title: rest.isEmpty ? link.name : L("%@: %@", link.name, rest),
                                       subtitle: url.absoluteString, keywords: text, icon: .symbol("link", .blue), remember: false) {
                    NSWorkspace.shared.open(url)
                })
            }
        }

        // Um endereço digitado ("github.com/quost", "https://…") abre direto
        if out.isEmpty, !text.contains(" "), text.contains("."), let url = Self.webAddress(text) {
            out.append(PaletteItem(id: "link.open", kind: .calc, title: L("Abrir %@", url.host() ?? text), subtitle: url.absoluteString,
                                   keywords: text, icon: .symbol("safari", .blue), remember: false) { NSWorkspace.shared.open(url) })
        }
        return out
    }

    /// No fim da lista: buscar o que foi digitado na web, com o primeiro link de busca da lista
    func webSearchItem(raw: String) -> PaletteItem? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let word = String(text.split(separator: " ").first ?? "").lowercased()
        guard text.count >= 2, !links.contains(where: { $0.keyword.lowercased() == word }),
              let engine = links.first(where: \.needsText), let url = engine.url(for: text) else { return nil }
        return PaletteItem(id: "link.search", kind: .action, title: L("Buscar “%@” no %@", text, engine.name), subtitle: url.absoluteString,
                           keywords: "", icon: .symbol("magnifyingglass", .blue), remember: false) { NSWorkspace.shared.open(url) }
    }

    private static func webAddress(_ text: String) -> URL? {
        let full = text.hasPrefix("http://") || text.hasPrefix("https://") ? text : "https://" + text
        guard let url = URL(string: full), let host = url.host(), host.contains("."),
              let tld = host.split(separator: ".").last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return nil }
        return url
    }
}

/// Ajustes → Links rápidos
struct QuickLinkSettings: View {
    @ObservedObject var store = QuickLinkStore.shared
    @State private var keyword = ""
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        GlassSection(title: L("Links rápidos"),
                     footer: L("Na paleta, digite a palavra e o que buscar: “jira ABC-123”, “gh menew”. Use {q} no endereço onde o texto entra.")) {
            ForEach(store.links) { link in
                SettingRow(title: link.keyword, detail: link.url) {
                    Button { store.remove(link) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(L("Remover"))
                }
                RowDivider()
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField(L("Palavra"), text: $keyword).frame(width: 70)
                    TextField(L("Nome"), text: $name).frame(width: 90)
                    TextField("https://exemplo.com/busca?q={q}", text: $url)
                }
                .textFieldStyle(.roundedBorder).font(.system(size: 11.5))
                HStack {
                    Spacer()
                    PillButton(title: L("Adicionar"), icon: "plus") {
                        let k = keyword.trimmingCharacters(in: .whitespaces), u = url.trimmingCharacters(in: .whitespaces)
                        guard !k.isEmpty, !k.contains(" "), u.contains("://") else { return }
                        store.add(QuickLink(keyword: k, name: name.isEmpty ? k : name, url: u))
                        keyword = ""; name = ""; url = ""
                    }
                    .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty || !url.contains("://"))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}
