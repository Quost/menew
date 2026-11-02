import AppKit
import SwiftUI

/// Janela da Memória: busca no topo, os cartões no meio e os detalhes do escolhido à direita
/// A memória mora na janela Menew
@MainActor
enum MemoryWindow {
    static let shared = Opener()
    struct Opener {
        @MainActor func show(query: String? = nil) {
            if let query { MemoryStore.shared.query = query }
            MemoryStore.shared.enrichPending()
            MenewWindow.shared.show(.memory)
        }
    }
}

struct MemoryView: View {
    @ObservedObject var store: MemoryStore
    @State private var confirmErase = false

    private var list: [MemoryItem] { store.filtered }
    private var current: MemoryItem? { store.items.first { $0.id == store.selectedID } ?? list.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                MemoryAnswerView().padding(.horizontal, 16).padding(.top, 6)
                if store.items.isEmpty {
                    empty
                } else if list.isEmpty {
                    Text(L("Nada encontrado")).font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 12)], spacing: 12) {
                            ForEach(list) { item in
                                RecallCard(item: item, image: store.image(for: item), on: item.id == current?.id)
                                    .onTapGesture { store.selectedID = item.id }
                                    .contextMenu { Button(L("Apagar"), role: .destructive) { store.delete(item) } }
                            }
                        }
                        .padding(16)
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let current {
                Divider()
                MemoryDetail(item: current, image: store.image(for: current)) { store.delete(current) }
                    .frame(width: 330)
                    .id(current.id)
            }
        }
        .background(Theme.windowFill)
        .confirmationDialog(L("Apagar toda a memória?"), isPresented: $confirmErase) {
            Button(L("Apagar"), role: .destructive) { store.eraseAll() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Buscar ou perguntar, ex.: qual era a biblioteca de gráficos?"), text: $store.query).textFieldStyle(.plain)
                    .onSubmit { if MemoryAsk.shared.available { MemoryAsk.shared.ask(store.query) } }
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
            if MemoryAsk.shared.available && !store.query.isEmpty {
                PillButton(title: L("Perguntar"), icon: "sparkles") { MemoryAsk.shared.ask(store.query) }
                    .help(L("A IA procura na memória, nas notas e no clipboard e responde com as fontes (↩)"))
            }
            Text(L("%d itens", list.count)).font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
            PillButton(title: L("Capturar"), icon: "plus.viewfinder", primary: true) { MemoryStore.shared.capture() }
                .help(Shortcut.load(MemoryStore.shortcutKey, default: .memoryDefault).display)
            Menu {
                Button(L("Guardar o texto copiado")) {
                    if let t = NSPasteboard.general.string(forType: .string) { store.add(text: t) }
                }
                Button(L("Mostrar a pasta no Finder")) { if let d = store.dir { NSWorkspace.shared.open(d) } }
                Divider()
                Button(L("Apagar toda a memória…"), role: .destructive) { confirmErase = true }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 16).padding(.bottom, 4)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile").font(.system(size: 40, weight: .light)).foregroundStyle(.pink)
            Text(L("Nunca mais perca o que passou pela sua tela")).font(.system(size: 16, weight: .semibold))
            Text(L("Aperte %@ e escolha uma área ou janela. O Menew guarda a imagem, lê o texto e anota de onde veio (app, janela e link). Depois é só buscar aqui ou na paleta.",
                   Shortcut.load(MemoryStore.shortcutKey, default: .memoryDefault).display))
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Text(L("Só guarda quando você pede. Fica tudo no seu Mac.")).font(.system(size: 11.5)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RecallCard: View {
    let item: MemoryItem
    let image: NSImage?
    let on: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05))
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.kind == .link ? "link" : "text.alignleft").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
            HStack(spacing: 4) {
                if let app = item.app { Text(app).lineLimit(1) }
                Text("·")
                Text(item.date, style: .relative).lineLimit(1)
            }
            .font(.system(size: 10.5)).foregroundStyle(.secondary)
            if !item.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.tags.prefix(3), id: \.self) { MemoryTag($0) }
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
    }
}

struct MemoryTag: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.pink.opacity(0.12))).foregroundStyle(.pink)
    }
}

struct MemoryDetail: View {
    let item: MemoryItem
    let image: NSImage?
    var onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let image {
                    LiveTextImage(image: image).aspectRatio(image.size, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10)).frame(maxHeight: 220)
                }
                Text(item.title).font(.system(size: 16, weight: .semibold)).textSelection(.enabled)
                if !item.summary.isEmpty {
                    Text(item.summary).font(.system(size: 12.5)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if !item.tags.isEmpty || !item.entities.isEmpty {
                    FlowTags(tags: item.tags + item.entities.filter { e in !item.tags.contains(e.lowercased()) })
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let app = item.app { row("app.badge", item.window.map { "\(app) · \($0)" } ?? app) }
                    row("clock", item.date.formatted(date: .abbreviated, time: .shortened))
                    if let url = item.url, let u = URL(string: url) {
                        Button { NSWorkspace.shared.open(u) } label: { row("link", u.host ?? url) }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    }
                }
                if !item.text.isEmpty {
                    Text(item.text).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }
                HStack(spacing: 8) {
                    if !item.text.isEmpty {
                        PillButton(title: L("Copiar texto"), icon: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.text, forType: .string)
                            HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
                        }
                    }
                    if let image {
                        PillButton(title: L("Copiar imagem"), icon: "photo") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([image])
                            HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
                        }
                    }
                    Spacer()
                    IconButton(icon: "trash", help: L("Apagar"), action: onDelete)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.never)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        Label { Text(text).lineLimit(2) } icon: { Image(systemName: icon).frame(width: 14) }
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
    }
}

/// Etiquetas que quebram linha
struct FlowTags: View {
    let tags: [String]
    var body: some View {
        FlowLayout(spacing: 5) { ForEach(tags, id: \.self) { MemoryTag($0) } }
    }
}
