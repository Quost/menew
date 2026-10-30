import Combine
import SwiftUI

/// Aba Notas: lista com busca e tags; ao abrir uma nota, editor com modo leitura (Markdown)
struct NotesView: View {
    @ObservedObject var store: NotesStore
    var nav: PopoverState?
    @State private var openID: UUID?
    @State private var query = ""
    @State private var tag: String?

    init(store: NotesStore, nav: PopoverState? = nil, openID: UUID? = nil) {
        self.store = store
        self.nav = nav
        _openID = State(initialValue: openID)
    }

    var body: some View {
        Group {
            // Uma nota protegida que foi trancada (menu fechado, Mac travado) volta para a lista
            if let id = openID, store.note(id) != nil, !store.isLocked(id) {
                NoteEditor(store: store, id: id, onTag: { t in tag = t; openID = nil }) { store.lock(id); openID = nil }
            } else {
                list
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
        .onDisappear { store.lockAll() }
        .onAppear(perform: openRequested)
        .onReceive(nav?.$noteToOpen.compactMap { $0 }.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in openRequested() }
    }

    /// Nota escolhida na paleta; a protegida pede Touch ID antes
    private func openRequested() {
        guard let id = nav?.noteToOpen else { return }
        nav?.noteToOpen = nil
        query = ""
        tag = nil
        if store.isLocked(id) {
            Task { if await store.unlock(id) { openID = id } }
        } else {
            openID = id
        }
    }

    private var list: some View {
        let notes = store.filtered(query: query, tag: tag)
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Buscar notas"), text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 13))
                .glassField()
                IconButton(icon: "key.fill", help: L("Nova nota de senhas")) { openID = store.createPasswords() }
                PillButton(title: L("Nova"), icon: "square.and.pencil", primary: true) {
                    openID = store.create(text: tag.map { "\n\n#\($0)" } ?? "")
                }
            }

            if !store.allTags.isEmpty {
                ScrollView(.horizontal) {
                    GlassGroup(spacing: 6) {
                        HStack(spacing: 6) {
                            GlassChip(title: L("Todas"), on: tag == nil) { tag = nil }
                            ForEach(store.allTags, id: \.self) { t in
                                GlassChip(title: "#\(t)", on: tag == t) { tag = tag == t ? nil : t }
                            }
                        }
                        .padding(2)
                    }
                }
                .noLiquidGlass()
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
                .noLiquidGlass()
                .scrollIndicators(.never)
            }
        }
    }

    private func row(_ n: Note) -> some View {
        Button { open(n) } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(n.isPasswords ? AnyShapeStyle(Color.blue.gradient)
                              : n.secure ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color.yellow.gradient))
                    Image(systemName: n.isPasswords ? "key.fill" : n.secure ? "lock.fill" : "note.text")
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
            if !n.isPasswords {
            Button(n.secure ? L("Remover proteção") : L("Proteger com Touch ID")) {
                Task {
                    if n.secure { guard await store.unlock(n.id) else { return } }
                    store.setSecure(!n.secure, for: n.id)
                }
            }
            }
            Divider()
            Button(L("Apagar"), role: .destructive) { store.delete(n.id) }
        }
    }

    private func open(_ n: Note) {
        guard n.secure else { openID = n.id; return }
        Task { if await store.unlock(n.id) { openID = n.id } }
    }

    private func copy(_ n: Note) {
        Task {
            if n.secure { guard await store.unlock(n.id) else { return } }
            if n.isPasswords { SecretCopy.copy(store.text(of: n.id)); return }
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
                if note?.isPasswords != true {
                    GlassSegmented(selection: $reading, options: [
                        .init(value: false, icon: "pencil", help: L("Editar")),
                        .init(value: true, icon: "eye", help: L("Ler")),
                    ], expand: false)
                }
                Menu {
                    Button(L("Copiar")) {
                        if note?.isPasswords == true { SecretCopy.copy(store.text(of: id)); return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.text(of: id), forType: .string)
                    }
                    Picker(L("Tipo"), selection: Binding(get: { note?.kind ?? .text }, set: { store.setKind($0, for: id) })) {
                        ForEach(Note.Kind.allCases, id: \.self) { k in Label(k.title, systemImage: k.icon).tag(k) }
                    }
                    if note?.isPasswords != true {
                        Button(note?.secure == true ? L("Remover proteção") : L("Proteger com Touch ID")) {
                            store.setSecure(!(note?.secure ?? false), for: id)
                        }
                    }
                    Divider()
                    Button(L("Apagar nota"), role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                        .glass(in: Circle(), interactive: true)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }

            Group {
                if note?.isPasswords == true {
                    PasswordsEditor(store: store, id: id)
                } else if reading {
                    ScrollView {
                        MarkdownView(text: store.text(of: id), onToggleTask: toggleTask, onTag: onTag)
                            .padding(4)
                    }
                    .noLiquidGlass()
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
        .onAppear { if note?.isPasswords != true, !reading || store.text(of: id).isEmpty { reading = false; focused = true } }
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

/// Nota de senhas: título e linhas de chave e valor. Valores escondidos, com olhinho para mostrar e botão de copiar.
private struct PasswordsEditor: View {
    @ObservedObject var store: NotesStore
    let id: UUID
    @State private var title = ""
    @State private var fields: [SecretField] = []
    @State private var shown: Set<UUID> = []
    @FocusState private var focus: Focus?

    enum Focus: Hashable { case title, key(UUID), value(UUID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField(L("Título (ex.: Wi-Fi de casa)"), text: $title)
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                    .focused($focus, equals: .title)
                    .padding(.horizontal, 4).padding(.bottom, 2)
                ForEach($fields) { $f in row($f) }
                Button {
                    let f = SecretField(key: "", value: "")
                    fields.append(f)
                    focus = .key(f.id)
                } label: {
                    Label(L("Adicionar campo"), systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.violet)
                }
                .buttonStyle(.plain).padding(.horizontal, 4).padding(.top, 2)
            }
            .padding(2)
        }
        .noLiquidGlass()
        .scrollIndicators(.never)
        .onAppear {
            let parsed = SecretField.parse(store.text(of: id))
            title = parsed.title
            fields = parsed.fields
            if title.isEmpty { focus = .title }
        }
        .onChange(of: title) { save() }
        .onChange(of: fields) { save() }
    }

    private func row(_ f: Binding<SecretField>) -> some View {
        let fid = f.wrappedValue.id
        let visible = shown.contains(fid)
        return HStack(spacing: 8) {
            TextField(L("Nome"), text: f.key)
                .textFieldStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                .focused($focus, equals: .key(fid))
                .frame(width: keyWidth)
            Group {
                if visible {
                    TextField(L("Valor"), text: f.value)
                } else {
                    SecureField(L("Valor"), text: f.value)
                }
            }
            .textFieldStyle(.plain).font(.system(size: 12.5, design: .monospaced))
            .focused($focus, equals: .value(fid))
            iconButton(visible ? "eye.slash" : "eye", help: visible ? L("Esconder") : L("Mostrar")) {
                if visible { shown.remove(fid) } else { shown.insert(fid) }
            }
            iconButton("doc.on.doc", help: L("Copiar")) { SecretCopy.copy(f.wrappedValue.value) }
                .disabled(f.wrappedValue.value.isEmpty)
            iconButton("minus.circle", help: L("Remover campo")) {
                fields.removeAll { $0.id == fid }
                shown.remove(fid)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    /// Coluna dos nomes do tamanho do maior nome (entre 60 e 160 pt); o valor fica com o resto
    private var keyWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let widest = fields.map { ($0.key as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(160, max(60, ceil(widest) + 6))
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private func save() {
        let text = SecretField.format(title: title, fields: fields)
        if text != store.text(of: id) { store.setText(text, of: id) }
    }
}
