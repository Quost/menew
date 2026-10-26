import SwiftUI

/// Aba Notas: lista com busca e tags; ao abrir uma nota, editor com modo leitura (Markdown)
struct NotesView: View {
    @ObservedObject var store: NotesStore
    @State private var openID: UUID?
    @State private var query = ""
    @State private var tag: String?

    init(store: NotesStore, openID: UUID? = nil) {
        self.store = store
        _openID = State(initialValue: openID)
    }

    var body: some View {
        Group {
            if let id = openID, store.note(id) != nil {
                NoteEditor(store: store, id: id, onTag: { t in tag = t; openID = nil }) { openID = nil }
            } else {
                list
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
        .onDisappear { store.lockAll() }
    }

    private var list: some View {
        let notes = store.filtered(query: query, tag: tag)
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Buscar notas"), text: $query).textFieldStyle(.plain)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
                PillButton(title: L("Nova"), icon: "square.and.pencil", primary: true) {
                    openID = store.create(text: tag.map { "\n\n#\($0)" } ?? "")
                }
            }

            if !store.allTags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        chip(L("Todas"), on: tag == nil) { tag = nil }
                        ForEach(store.allTags, id: \.self) { t in
                            chip("#\(t)", on: tag == t) { tag = tag == t ? nil : t }
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            if notes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "note.text").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                    Text(store.notes.isEmpty ? L("Nenhuma nota ainda") : L("Nada encontrado"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    if store.notes.isEmpty {
                        Text(L("Use #tags no texto para organizar e **negrito**, listas e - [ ] tarefas em Markdown."))
                            .font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(notes) { n in row(n) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func row(_ n: Note) -> some View {
        Button { open(n) } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(n.secure ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color.yellow.gradient))
                    Image(systemName: n.secure ? "lock.fill" : "note.text")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(n.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(RelDate.string(n.updated)).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                    if !n.preview.isEmpty {
                        Text(n.preview).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !n.tags.isEmpty {
                        Text(n.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.violet).lineLimit(1)
                    }
                }
            }
            .card(padding: 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L("Copiar")) { copy(n) }
            Button(n.secure ? L("Remover proteção") : L("Proteger com Touch ID")) {
                Task {
                    if n.secure { guard await store.unlock(n.id) else { return } }
                    store.setSecure(!n.secure, for: n.id)
                }
            }
            Divider()
            Button(L("Apagar"), role: .destructive) { store.delete(n.id) }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.06))))
                .foregroundStyle(on ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private func open(_ n: Note) {
        guard n.secure else { openID = n.id; return }
        Task { if await store.unlock(n.id) { openID = n.id } }
    }

    private func copy(_ n: Note) {
        Task {
            if n.secure { guard await store.unlock(n.id) else { return } }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(store.text(of: n.id), forType: .string)
        }
    }
}

private struct NoteEditor: View {
    @ObservedObject var store: NotesStore
    let id: UUID
    var onTag: (String) -> Void
    var onClose: () -> Void

    @AppStorage("notesReading") private var reading = false
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    private var text: Binding<String> {
        Binding(get: { store.text(of: id) }, set: { store.setText($0, of: id) })
    }

    var body: some View {
        let note = store.note(id)
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: L("Voltar"), action: onClose)
                if note?.secure == true {
                    Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.orange)
                }
                Text(note?.title ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Picker("", selection: $reading) {
                    Image(systemName: "pencil").tag(false)
                    Image(systemName: "eye").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 76)
                .help(reading ? L("Ler") : L("Editar"))
                Menu {
                    Button(L("Copiar")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.text(of: id), forType: .string)
                    }
                    Button(note?.secure == true ? L("Remover proteção") : L("Proteger com Touch ID")) {
                        store.setSecure(!(note?.secure ?? false), for: id)
                    }
                    Divider()
                    Button(L("Apagar nota"), role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 14))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }

            Group {
                if reading {
                    ScrollView {
                        MarkdownView(text: store.text(of: id), onToggleTask: toggleTask, onTag: onTag)
                            .padding(4)
                    }
                    .scrollIndicators(.never)
                } else {
                    ZStack(alignment: .topLeading) {
                        if store.text(of: id).isEmpty {
                            Text(L("Título na primeira linha…\nUse #tags, **negrito**, listas e - [ ] tarefas."))
                                .font(.system(size: 13)).foregroundStyle(.tertiary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: text)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .scrollContentBackground(.hidden)
                            .focused($focused)
                    }
                }
            }
            .card(padding: 10)

            HStack(spacing: 6) {
                Image(systemName: note?.secure == true ? "lock.shield" : "checkmark.icloud")
                    .foregroundStyle(note?.secure == true ? .orange : .green)
                Text(note?.secure == true ? L("Protegida nas Chaves do macOS") : L("Salvo · %d caracteres", store.text(of: id).count))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.system(size: 11))
        }
        .onAppear { if !reading || store.text(of: id).isEmpty { reading = false; focused = true } }
        .confirmationDialog(L("Apagar esta nota?"), isPresented: $confirmDelete) {
            Button(L("Apagar"), role: .destructive) { store.delete(id); onClose() }
        }
    }

    /// Marca/desmarca "- [ ]" na linha clicada do modo leitura
    private func toggleTask(_ line: Int) {
        var lines = store.text(of: id).components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return }
        let l = lines[line]
        if l.contains("[ ]") {
            lines[line] = l.replacingOccurrences(of: "[ ]", with: "[x]", options: [], range: l.range(of: "[ ]"))
        } else if let r = l.range(of: "[x]") ?? l.range(of: "[X]") {
            lines[line] = l.replacingCharacters(in: r, with: "[ ]")
        }
        store.setText(lines.joined(separator: "\n"), of: id)
    }
}
