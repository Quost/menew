import AppKit
import CryptoKit
import SwiftUI

// Telas do compartilhamento de senhas, dentro da aba Notas: mandar, receber, e o código e os contatos.

/// Mandar uma nota protegida: escolher os campos e para quem, e sai um arquivo `.menewsecret` para arrastar
struct ShareSecretView: View {
    @ObservedObject var store: NotesStore
    let id: UUID
    var onClose: () -> Void
    @ObservedObject private var keys = ShareKeys.shared

    enum Mode: Hashable { case contact, passphrase }

    @State private var mode: Mode = .contact
    @State private var title = ""
    @State private var fields: [SecretField] = []
    @State private var included: Set<UUID> = []
    @State private var recipient: UUID?
    @State private var passphrase = SecretShare.generatePassphrase()
    @State private var adding = false
    @State private var working = false
    @State private var file: URL?
    @State private var failed = false

    init(store: NotesStore, id: UUID, recipient: UUID? = nil, mode: Mode? = nil, onClose: @escaping () -> Void) {
        self.store = store
        self.id = id
        self.onClose = onClose
        _recipient = State(initialValue: recipient)
        _forcedMode = State(initialValue: mode)
    }
    @State private var forcedMode: Mode?

    private var isPasswords: Bool { store.note(id)?.isPasswords == true }
    private var chosen: ShareContact? { keys.contacts.first { $0.id == recipient } }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: L("Voltar"), action: onClose)
                Image(systemName: "paperplane.fill").font(.system(size: 11)).foregroundStyle(Theme.violet)
                Text(L("Compartilhar «%@»", title)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 10) {
                    if let file { result(file) } else { what; who }
                }
                .padding(.bottom, 4)
            }
            .noLiquidGlass()
            .scrollIndicators(.never)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").foregroundStyle(.green)
                Text(L("Criptografado no seu Mac. Nada passa pela internet.")).foregroundStyle(.secondary)
                Spacer()
                if file == nil {
                    if working { ProgressView().controlSize(.small) }
                    PillButton(title: L("Criar arquivo"), icon: "lock.doc.fill", primary: true, action: create)
                        .disabled(!ready || working).opacity(ready ? 1 : 0.5)
                } else {
                    PillButton(title: L("Pronto"), primary: true, action: onClose)
                }
            }
            .font(.system(size: 11))
        }
        .onAppear(perform: load)
    }

    private var ready: Bool {
        (!isPasswords || !included.isEmpty) && (mode == .passphrase || chosen?.publicKey != nil)
    }

    private func load() {
        let text = store.text(of: id)
        let parsed = SecretField.parse(text)
        title = parsed.title.isEmpty ? (store.note(id)?.title ?? "") : parsed.title
        if isPasswords {
            fields = parsed.fields.filter { !$0.value.isEmpty }
            included = Set(fields.map(\.id))
        }
        if let forcedMode { mode = forcedMode } else if keys.contacts.isEmpty { mode = .passphrase }
        if recipient == nil, keys.contacts.count == 1 { recipient = keys.contacts[0].id }
    }

    // O que vai
    @ViewBuilder private var what: some View {
        VStack(alignment: .leading, spacing: 6) {
            section(L("O que vai"))
            if isPasswords {
                if fields.isEmpty {
                    Text(L("Esta nota não tem campos preenchidos.")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(fields) { f in
                    Toggle(isOn: Binding(get: { included.contains(f.id) },
                                         set: { if $0 { included.insert(f.id) } else { included.remove(f.id) } })) {
                        HStack(spacing: 6) {
                            Text(f.key.isEmpty ? L("Sem nome") : f.key).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(String(repeating: "•", count: min(max(f.value.count, 4), 10)))
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            } else {
                Text(L("A nota inteira vai no arquivo.")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .card(padding: 12)
    }

    // Para quem
    private var who: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(L("Para quem"))
            GlassSegmented(selection: $mode, options: [
                .init(value: .contact, title: L("Para um contato"), icon: "person.fill"),
                .init(value: .passphrase, title: L("Com senha"), icon: "key.horizontal.fill"),
            ])
            if mode == .contact { contactPicker } else { passphraseBox }
        }
        .card(padding: 12)
    }

    @ViewBuilder private var contactPicker: some View {
        if keys.contacts.isEmpty && !adding {
            Text(L("Peça o código Menew da pessoa e adicione aqui. Só o Mac dela vai conseguir abrir o arquivo."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        ForEach(keys.contacts) { c in
            Button { recipient = c.id } label: {
                HStack(spacing: 8) {
                    Image(systemName: recipient == c.id ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(recipient == c.id ? Theme.violet : .secondary)
                    Text(c.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(c.fingerprint).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if adding {
            AddContactForm(onAdded: { c in recipient = c.id; adding = false }, onCancel: { adding = false })
        } else {
            Button { adding = true } label: {
                Label(L("Adicionar contato"), systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.violet)
            }
            .buttonStyle(.plain)
        }
    }

    private var passphraseBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(passphrase).font(.system(size: 16, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                Spacer(minLength: 4)
                smallButton("arrow.clockwise", help: L("Gerar outra")) { passphrase = SecretShare.generatePassphrase() }
                smallButton("doc.on.doc", help: L("Copiar")) { SecretCopy.copy(passphrase) }
            }
            warning(L("Mande a senha por outro caminho (ligação, SMS ou em pessoa), nunca no mesmo chat do arquivo."))
        }
    }

    private func result(_ file: URL) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: "lock.doc.fill").font(.system(size: 40)).foregroundStyle(Theme.violet.gradient)
                Text(file.lastPathComponent).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(L("Arraste para o Teams, o Slack ou um e-mail")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(.secondary.opacity(0.5)))
            .contentShape(Rectangle())
            .onDrag { NSItemProvider(object: file as NSURL) }
            .help(L("Arraste para o Teams, o Slack ou um e-mail"))

            HStack(spacing: 8) {
                ShareLink(item: file) {
                    Label(L("Compartilhar…"), systemImage: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
                }
                PillButton(title: L("Mostrar no Finder"), icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
            }

            if mode == .contact, let chosen {
                Label(L("Só %@ consegue abrir este arquivo.", chosen.name), systemImage: "person.badge.key.fill")
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Quem receber vai precisar desta senha:")).font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Text(passphrase).font(.system(size: 16, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        smallButton("doc.on.doc", help: L("Copiar")) { SecretCopy.copy(passphrase) }
                    }
                    warning(L("Mande a senha por outro caminho (ligação, SMS ou em pessoa), nunca no mesmo chat do arquivo."))
                }
                .card(padding: 12)
            }
            if failed { warning(L("Não deu para criar o arquivo")) }
        }
    }

    private func create() {
        let text = isPasswords
            ? SecretField.format(title: title, fields: fields.filter { included.contains($0.id) })
            : store.text(of: id)
        let payload = SecretPayload(text: text, kind: isPasswords ? .passwords : .text, sender: NSFullUserName())
        let me = keys.identity
        let to = chosen?.publicKey
        let mode = mode, pass = passphrase, title = title
        working = true
        failed = false
        Task {
            // 600 mil rodadas de PBKDF2 levam um instante: fora da thread principal
            let env = await Task.detached { () -> SecretEnvelope? in
                if mode == .contact, let to { return try? SecretShare.seal(payload, from: me, to: to) }
                return try? SecretShare.seal(payload, passphrase: pass)
            }.value
            working = false
            guard let env, let url = try? keys.write(env, title: title) else { failed = true; return }
            withAnimation(.spring(duration: 0.3)) { file = url }
        }
    }
}

/// O código deste Mac, os contatos e o botão de importar
struct ShareCenterView: View {
    var onClose: () -> Void
    @ObservedObject private var keys = ShareKeys.shared
    @State private var adding = false
    @State private var copied = false
    @State private var hovering: UUID?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: L("Voltar"), action: onClose)
                Text(L("Compartilhar senhas")).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            ScrollView {
                VStack(spacing: 10) {
                    myCode
                    contacts
                    receive
                }
                .padding(.bottom, 4)
            }
            .noLiquidGlass()
            .scrollIndicators(.never)
        }
    }

    private var myCode: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(L("Meu código Menew"))
            Text(L("Mande este código para quem vai te enviar senhas. Ele é público: pode ir pelo chat."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(keys.myCode).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Text(L("Conferência: %@", keys.myFingerprint)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                PillButton(title: copied ? L("Copiado") : L("Copiar código"), icon: copied ? "checkmark" : "doc.on.doc", primary: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(keys.myCodeToCopy, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                }
            }
        }
        .card(padding: 12)
    }

    private var contacts: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(L("Contatos"))
            if keys.contacts.isEmpty && !adding {
                Text(L("Adicione o código de quem vai receber senhas suas. Só o Mac da pessoa abre o que você mandar."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(keys.contacts) { c in
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.violet.opacity(0.8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        Text(c.fingerprint).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if hovering == c.id {
                        Button { keys.remove(c.id) } label: {
                            Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain).help(L("Remover contato"))
                    }
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 ? c.id : (hovering == c.id ? nil : hovering) }
                .contextMenu { Button(L("Remover contato"), role: .destructive) { keys.remove(c.id) } }
            }
            if adding {
                AddContactForm(onAdded: { _ in adding = false }, onCancel: { adding = false })
            } else {
                Button { adding = true } label: {
                    Label(L("Adicionar contato"), systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.violet)
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 12)
    }

    private var receive: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(L("Receber"))
            Text(L("Solte o arquivo .menewsecret no notch, abra com dois cliques ou escolha aqui."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            PillButton(title: L("Importar arquivo…"), icon: "tray.and.arrow.down") {
                if let url = keys.pickFile() { keys.pendingImport = url }
            }
        }
        .card(padding: 12)
    }
}

/// Colar o código de alguém: o nome vem junto quando a pessoa copiou pelo Menew
struct AddContactForm: View {
    var onAdded: (ShareContact) -> Void
    var onCancel: () -> Void
    @ObservedObject private var keys = ShareKeys.shared
    @State private var code = ""
    @State private var name = ""
    @FocusState private var focused: Bool

    private var parsed: (key: Curve25519.KeyAgreement.PublicKey, name: String)? { SecretShare.parseCode(code) }
    private var isMine: Bool { parsed?.key.rawRepresentation == keys.identity.publicKey.rawRepresentation }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L("Cole o código Menew da pessoa"), text: $code)
                .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).glassField()
                .focused($focused)
            TextField(L("Nome"), text: $name).textFieldStyle(.plain).font(.system(size: 12.5)).glassField()
            if let parsed {
                if isMine {
                    warning(L("Este é o seu próprio código"))
                } else {
                    Text(L("Confira com a pessoa: %@", SecretShare.fingerprint(parsed.key.rawRepresentation)))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            } else if !code.isEmpty {
                warning(L("Código inválido"))
            }
            HStack {
                Spacer()
                PillButton(title: L("Cancelar"), action: onCancel)
                PillButton(title: L("Adicionar"), icon: "person.badge.plus", primary: true) {
                    guard let parsed, !isMine else { return }
                    onAdded(keys.add(name: name, key: parsed.key))
                }
                .disabled(parsed == nil || isMine).opacity(parsed == nil || isMine ? 0.5 : 1)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
        .onAppear {
            // Código copiado agora há pouco: já vem colado
            if let s = NSPasteboard.general.string(forType: .string), SecretShare.parseCode(s) != nil { code = s }
            focused = code.isEmpty
        }
        .onChange(of: code) {
            guard let p = parsed else { return }
            if name.isEmpty, !p.name.isEmpty { name = p.name }
            // Fica só o código no campo; o nome foi para o outro
            let clean = SecretShare.code(for: p.key)
            if code != clean { code = clean }
        }
    }
}

/// Arquivo recebido: abre (com a chave deste Mac ou a senha), mostra o que tem e salva como nota protegida
struct ImportSecretView: View {
    let url: URL
    @ObservedObject var store: NotesStore
    var onDone: (UUID?) -> Void
    @ObservedObject private var keys = ShareKeys.shared

    @State private var env: SecretEnvelope?
    @State private var problem: SecretShareError?
    @State private var secret: SecretPayload?
    @State private var sender: Curve25519.KeyAgreement.PublicKey?
    @State private var passphrase = ""
    @State private var opening = false
    @State private var saveContact = true
    @State private var contactName = ""
    @FocusState private var focused: Bool

    private var known: ShareContact? { sender.flatMap { keys.contact(for: $0) } }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: L("Descartar")) { onDone(nil) }
                Image(systemName: "lock.doc.fill").font(.system(size: 11)).foregroundStyle(Theme.violet)
                Text(L("Segredo recebido")).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill").foregroundStyle(.secondary)
                        Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                    }
                    .card(padding: 10)
                    content
                }
                .padding(.bottom, 4)
            }
            .noLiquidGlass()
            .scrollIndicators(.never)
            if secret != nil {
                HStack {
                    Image(systemName: "lock.shield").foregroundStyle(.orange)
                    Text(L("Vira uma nota protegida nas Chaves do macOS")).foregroundStyle(.secondary)
                    Spacer()
                    PillButton(title: L("Salvar nas notas"), icon: "square.and.arrow.down", primary: true, action: save)
                }
                .font(.system(size: 11))
            }
        }
        .onAppear(perform: read)
        .onChange(of: url) { read() }
    }

    @ViewBuilder private var content: some View {
        if let problem, problem != .wrongPassphrase {
            VStack(spacing: 8) {
                Image(systemName: problem == .notForMe ? "person.crop.circle.badge.xmark" : "exclamationmark.triangle.fill")
                    .font(.system(size: 28)).foregroundStyle(.orange)
                Text(message(problem)).font(.system(size: 12.5)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity).card(padding: 16)
        } else if let secret {
            opened(secret)
        } else if env?.mode == .passphrase {
            VStack(alignment: .leading, spacing: 8) {
                section(L("Senha"))
                Text(L("Digite a senha que a pessoa te passou.")).font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("xxxx-xxxx-xxxx-xxxx", text: $passphrase)
                        .textFieldStyle(.plain).font(.system(size: 14, design: .monospaced)).glassField()
                        .focused($focused).onSubmit(openWithPassphrase)
                    if opening { ProgressView().controlSize(.small) }
                    PillButton(title: L("Abrir"), icon: "lock.open.fill", primary: true, action: openWithPassphrase)
                        .disabled(passphrase.isEmpty || opening)
                }
                if problem == .wrongPassphrase { warning(L("Senha errada")) }
            }
            .card(padding: 12)
            .onAppear { focused = true }
        }
    }

    private func opened(_ s: SecretPayload) -> some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                fromLine(s)
                Text(s.title.isEmpty ? L("Nota sem título") : s.title).font(.system(size: 15, weight: .semibold))
                if s.kind == .passwords {
                    ForEach(Array(s.fieldNames.enumerated()), id: \.offset) { _, name in
                        HStack {
                            Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            Spacer()
                            Text("••••••••").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
                    }
                } else {
                    Text(L("Nota protegida · %d caracteres", s.text.count)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .card(padding: 12)
            // Remetente fora dos contatos: dá para guardar para responder depois
            if env?.mode == .contact, known == nil, let sender {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(L("Salvar nos contatos"), isOn: $saveContact).toggleStyle(.checkbox).font(.system(size: 12))
                    if saveContact {
                        TextField(L("Nome"), text: $contactName).textFieldStyle(.plain).font(.system(size: 12.5)).glassField()
                    }
                    Text(L("Conferência: %@", SecretShare.fingerprint(sender.rawRepresentation)))
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary)
                }
                .card(padding: 12)
            }
        }
    }

    @ViewBuilder private func fromLine(_ s: SecretPayload) -> some View {
        if env?.mode == .contact {
            if let known {
                Label(L("De %@ · verificado", known.name), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.green)
            } else {
                Label(s.sender.map { L("De %@ · fora dos seus contatos", $0) } ?? L("De alguém fora dos seus contatos"),
                      systemImage: "questionmark.circle.fill")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.orange)
            }
        } else if let name = s.sender, !name.isEmpty {
            Label(L("Enviado por %@", name), systemImage: "key.horizontal.fill")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private func message(_ e: SecretShareError) -> String {
        switch e {
        case .notASecret: L("Este arquivo não é um segredo do Menew.")
        case .newerVersion: L("Este arquivo veio de uma versão mais nova do Menew. Atualize para abrir.")
        case .notForMe: L("Este arquivo foi criado para outra pessoa. Só o Mac dela consegue abrir.")
        case .damaged: L("O arquivo está corrompido ou foi alterado.")
        case .wrongPassphrase: L("Senha errada")
        }
    }

    private func read() {
        env = nil; secret = nil; sender = nil; problem = nil; passphrase = ""
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { problem = .notASecret; return }
        do {
            let e = try SecretShare.decode(data)
            env = e
            if e.mode == .contact {
                let r = try SecretShare.open(e, with: keys.identity)
                secret = r.secret
                sender = r.sender
                contactName = r.secret.sender ?? ""
            }
        } catch let e as SecretShareError {
            problem = e
        } catch {
            problem = .damaged
        }
    }

    private func openWithPassphrase() {
        guard let env, !passphrase.isEmpty, !opening else { return }
        opening = true
        problem = nil
        let pass = passphrase
        Task {
            let r = await Task.detached { () -> Result<SecretPayload, SecretShareError> in
                do { return .success(try SecretShare.open(env, passphrase: pass)) } catch { return .failure(error as? SecretShareError ?? .damaged) }
            }.value
            opening = false
            switch r {
            case .success(let s): withAnimation(.spring(duration: 0.3)) { secret = s }
            case .failure(let e): problem = e
            }
        }
    }

    private func save() {
        guard let secret else { return }
        if env?.mode == .contact, known == nil, saveContact, let sender { keys.add(name: contactName, key: sender) }
        let id = store.createProtected(secret.text, kind: secret.kind)
        HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Segredo salvo nas notas"))
        onDone(id)
    }
}

// MARK: Pedaços em comum

private func section(_ title: String) -> some View {
    Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.4)
}

private func warning(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
}

private func smallButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .frame(width: 26, height: 22).contentShape(Rectangle())
    }
    .buttonStyle(.plain).help(help).accessibilityLabel(help)
}
