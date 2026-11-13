import AppKit
import CommonCrypto
import CryptoKit
import Foundation
import Security
import UniformTypeIdentifiers

// Compartilhar senhas sem mandar o texto cru pelo chat: o Menew gera um arquivo `.menewsecret` criptografado.
//
// Dois modos:
// - Para um contato: cada Menew tem um par de chaves X25519 (a privada fica nas Chaves do macOS). A pessoa manda
//   o "código Menew" dela, que é a chave pública, e o arquivo só abre no Mac dela. O remetente também assina com a
//   chave dele (dois acordos de chave, como no Noise), então quem recebe sabe de quem veio.
// - Com senha: uma senha gerada pelo Menew (≈79 bits), passada por outro caminho (ligação, SMS, em pessoa).
//   PBKDF2-SHA256 com 600 mil rodadas deriva a chave.
// Nos dois, o conteúdo vai em AES-GCM e o cabeçalho entra como dado autenticado. Nada passa pela rede.

/// O que vai dentro do arquivo, já descriptografado
struct SecretPayload: Codable, Equatable {
    /// Texto da nota no formato de sempre: título na primeira linha e, nas senhas, um "chave: valor" por linha
    var text: String
    var kind: Note.Kind
    /// Nome de quem mandou, como está no Mac dele (só informativo; quem confirma é a chave)
    var sender: String?
    var created = Date()

    var title: String { String(text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") }
    var fieldNames: [String] { kind == .passwords ? SecretField.parse(text).fields.map(\.key) : [] }
}

/// O arquivo como fica no disco (JSON)
struct SecretEnvelope: Codable, Equatable {
    enum Mode: String, Codable { case contact, passphrase }

    var menew = "secret"
    var v = 1
    var mode: Mode
    /// Modo contato: chaves públicas de quem mandou e de quem recebe, e a chave efêmera deste arquivo
    var from: String?
    var to: String?
    var eph: String?
    /// Modo senha
    var salt: String?
    var rounds: Int?
    /// AES-GCM (nonce + texto + tag)
    var box: String

    /// Tudo do cabeçalho entra como dado autenticado: trocar um campo invalida o arquivo
    var aad: Data {
        Data(["menew-secret", String(v), mode.rawValue, from ?? "", to ?? "", eph ?? "", salt ?? "", String(rounds ?? 0)]
            .joined(separator: "|").utf8)
    }
}

enum SecretShareError: Error, Equatable {
    case notASecret, newerVersion, notForMe, wrongPassphrase, damaged
}

enum SecretShare {
    static let fileExtension = "menewsecret"
    static let fileType = UTType(filenameExtension: fileExtension) ?? .data
    static let defaultRounds = 600_000
    private static let keyPrefix = "menew-key:"

    // MARK: Códigos (chaves públicas)

    static func code(for key: Curve25519.KeyAgreement.PublicKey) -> String {
        keyPrefix + base64url(key.rawRepresentation)
    }

    /// Acha um código num texto colado ("Ana Silva · menew-key:…"); o que vem antes vira a sugestão de nome
    static func parseCode(_ text: String) -> (key: Curve25519.KeyAgreement.PublicKey, name: String)? {
        guard let r = text.range(of: keyPrefix + "[A-Za-z0-9_-]{43}", options: .regularExpression),
              let raw = unbase64url(String(text[r].dropFirst(keyPrefix.count))),
              let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else { return nil }
        let name = text[..<r.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " ·:-–—\n\t"))
        return (key, String(name.prefix(60)))
    }

    /// Impressão digital curta para conferir por telefone: "4F2A·91C3·7B0E"
    static func fingerprint(_ raw: Data) -> String {
        let hex = SHA256.hash(data: raw).prefix(6).map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map { i in
            let a = hex.index(hex.startIndex, offsetBy: i)
            return String(hex[a..<hex.index(a, offsetBy: 4)])
        }.joined(separator: "·")
    }

    // MARK: Senha gerada

    /// 16 caracteres sem os que se confundem (i, l, o, 0, 1), em grupos de 4: fácil de ditar
    static func generatePassphrase() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        let chars = (0..<16).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] }
        return stride(from: 0, to: 16, by: 4).map { String(chars[$0..<$0 + 4]) }.joined(separator: "-")
    }

    /// Maiúsculas, espaços e traços não importam: a senha é sempre gerada pelo Menew
    static func normalize(_ passphrase: String) -> String {
        passphrase.lowercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    // MARK: Fechar

    static func seal(_ secret: SecretPayload, from sender: Curve25519.KeyAgreement.PrivateKey,
                     to recipient: Curve25519.KeyAgreement.PublicKey) throws -> SecretEnvelope {
        let eph = Curve25519.KeyAgreement.PrivateKey()
        var env = SecretEnvelope(mode: .contact, from: base64url(sender.publicKey.rawRepresentation),
                                 to: base64url(recipient.rawRepresentation), eph: base64url(eph.publicKey.rawRepresentation), box: "")
        let key = try contactKey(eph.sharedSecretFromKeyAgreement(with: recipient),
                                 sender.sharedSecretFromKeyAgreement(with: recipient), aad: env.aad)
        env.box = try box(secret, key: key, aad: env.aad)
        return env
    }

    static func seal(_ secret: SecretPayload, passphrase: String, rounds: Int = defaultRounds) throws -> SecretEnvelope {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        var env = SecretEnvelope(mode: .passphrase, salt: base64url(salt), rounds: rounds, box: "")
        guard let key = pbkdf2(normalize(passphrase), salt: salt, rounds: rounds) else { throw SecretShareError.damaged }
        env.box = try box(secret, key: key, aad: env.aad)
        return env
    }

    // MARK: Abrir

    static func decode(_ data: Data) throws -> SecretEnvelope {
        guard let env = try? JSONDecoder().decode(SecretEnvelope.self, from: data), env.menew == "secret" else {
            throw SecretShareError.notASecret
        }
        guard env.v == 1 else { throw SecretShareError.newerVersion }
        return env
    }

    /// Modo contato. Devolve também a chave pública de quem mandou, já comprovada pela própria abertura.
    static func open(_ env: SecretEnvelope, with me: Curve25519.KeyAgreement.PrivateKey) throws
        -> (secret: SecretPayload, sender: Curve25519.KeyAgreement.PublicKey) {
        guard env.mode == .contact, let fromRaw = env.from.flatMap(unbase64url), let ephRaw = env.eph.flatMap(unbase64url),
              let toRaw = env.to.flatMap(unbase64url),
              let from = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: fromRaw),
              let eph = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephRaw) else { throw SecretShareError.damaged }
        guard toRaw == me.publicKey.rawRepresentation else { throw SecretShareError.notForMe }
        let key = try contactKey(me.sharedSecretFromKeyAgreement(with: eph), me.sharedSecretFromKeyAgreement(with: from), aad: env.aad)
        return (try unbox(env.box, key: key, aad: env.aad, failure: .damaged), from)
    }

    static func open(_ env: SecretEnvelope, passphrase: String) throws -> SecretPayload {
        guard env.mode == .passphrase, let salt = env.salt.flatMap(unbase64url), let rounds = env.rounds,
              (10_000...10_000_000).contains(rounds),
              let key = pbkdf2(normalize(passphrase), salt: salt, rounds: rounds) else { throw SecretShareError.damaged }
        return try unbox(env.box, key: key, aad: env.aad, failure: .wrongPassphrase)
    }

    // MARK: Criptografia

    private static func contactKey(_ a: CryptoKit.SharedSecret, _ b: CryptoKit.SharedSecret, aad: Data) throws -> SymmetricKey {
        var ikm = a.withUnsafeBytes { Data($0) }
        ikm += b.withUnsafeBytes { Data($0) }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: aad,
                                      info: Data("menew-secret contact".utf8), outputByteCount: 32)
    }

    private static func box(_ secret: SecretPayload, key: SymmetricKey, aad: Data) throws -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let sealed = try AES.GCM.seal(try enc.encode(secret), using: key, authenticating: aad)
        guard let combined = sealed.combined else { throw SecretShareError.damaged }
        return base64url(combined)
    }

    private static func unbox(_ box: String, key: SymmetricKey, aad: Data, failure: SecretShareError) throws -> SecretPayload {
        guard let data = unbase64url(box), let sealed = try? AES.GCM.SealedBox(combined: data) else { throw SecretShareError.damaged }
        guard let plain = try? AES.GCM.open(sealed, using: key, authenticating: aad) else { throw failure }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let secret = try? dec.decode(SecretPayload.self, from: plain) else { throw SecretShareError.damaged }
        return secret
    }

    static func pbkdf2(_ passphrase: String, salt: Data, rounds: Int) -> SymmetricKey? {
        let pw = Array(passphrase.utf8)
        guard !pw.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { s in
            pw.withUnsafeBufferPointer { p in
                p.baseAddress!.withMemoryRebound(to: CChar.self, capacity: max(pw.count, 1)) { cp in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), cp, pw.count,
                                         s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds), &out, out.count)
                }
            }
        }
        return status == kCCSuccess ? SymmetricKey(data: out) : nil
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func unbase64url(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}

// MARK: Chave deste Mac e contatos

struct ShareContact: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Chave pública em base64url
    var key: String
    var added = Date()

    var publicKey: Curve25519.KeyAgreement.PublicKey? {
        SecretShare.unbase64url(key).flatMap { try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0) }
    }
    var fingerprint: String { SecretShare.unbase64url(key).map(SecretShare.fingerprint) ?? "" }
}

@MainActor
final class ShareKeys: ObservableObject {
    static let shared = ShareKeys()

    @Published private(set) var contacts: [ShareContact] = []
    /// Arquivo aberto (dois cliques, solto no notch): a aba Notas mostra a tela de importar
    @Published var pendingImport: URL?
    private var demoKey: Curve25519.KeyAgreement.PrivateKey?

    private var url: URL { AppData.dir.appendingPathComponent("share-contacts.json") }
    private static let service = "com.matheusquost.menew.share"

    private init() {
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([ShareContact].self, from: data) {
            contacts = list
        }
    }

    /// Chave deste Mac: criada na primeira vez, guardada nas Chaves do macOS, nunca sai daqui
    var identity: Curve25519.KeyAgreement.PrivateKey {
        if let demoKey { return demoKey }
        if let cachedKey { return cachedKey }
        let key = loadOrCreateIdentity()
        cachedKey = key
        return key
    }
    private var cachedKey: Curve25519.KeyAgreement.PrivateKey?

    private func loadOrCreateIdentity() -> Curve25519.KeyAgreement.PrivateKey {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
                                kSecAttrAccount as String: "identity"]
        var read = q
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        if SecItemCopyMatching(read as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        var add = q
        add[kSecValueData as String] = key.rawRepresentation
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrLabel as String] = "Menew sharing key"
        SecItemAdd(add as CFDictionary, nil)
        return key
    }

    var myCode: String { SecretShare.code(for: identity.publicKey) }
    var myFingerprint: String { SecretShare.fingerprint(identity.publicKey.rawRepresentation) }
    /// O que vai para a área de transferência: com o nome, quem cola já vê de quem é
    var myCodeToCopy: String { "\(NSFullUserName()) · \(myCode)" }

    func contact(for key: Curve25519.KeyAgreement.PublicKey) -> ShareContact? {
        let k = SecretShare.base64url(key.rawRepresentation)
        return contacts.first { $0.key == k }
    }

    @discardableResult
    func add(name: String, key: Curve25519.KeyAgreement.PublicKey) -> ShareContact {
        let k = SecretShare.base64url(key.rawRepresentation)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = contacts.firstIndex(where: { $0.key == k }) {
            if !clean.isEmpty { contacts[i].name = clean }
            save()
            return contacts[i]
        }
        let c = ShareContact(name: clean.isEmpty ? SecretShare.fingerprint(key.rawRepresentation) : clean, key: k)
        contacts.append(c)
        contacts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
        return c
    }

    func remove(_ id: UUID) {
        contacts.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard demoKey == nil, let data = try? JSONEncoder().encode(contacts) else { return }
        try? FileManager.default.createDirectory(at: AppData.dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Para as capturas de tela: chave e contatos fictícios, nada lido nem gravado
    func showDemo() {
        // Chaves fixas (derivadas de um texto): as capturas saem iguais a cada vez
        func key(_ seed: String) -> Curve25519.KeyAgreement.PrivateKey {
            (try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(SHA256.hash(data: Data(("menew-demo " + seed).utf8)))))
                ?? Curve25519.KeyAgreement.PrivateKey()
        }
        demoKey = key("me")
        let names = L10n.current == .pt ? ["Ana Souza", "Bruno Lima", "Equipe de infra"] : ["Ana Miller", "Ben Carter", "Infra team"]
        contacts = names.enumerated().map { i, n in ShareContact(name: n, key: SecretShare.base64url(key(String(i)).publicKey.rawRepresentation)) }
    }

    /// Arquivo de exemplo para a captura da tela de importar: mandado por "Ana" para este Mac
    func demoFile() -> URL? {
        guard let me = demoKey, let ana = contacts.first else { return nil }
        let from = (try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(SHA256.hash(data: Data("menew-demo 0".utf8)))))
        let text = SecretField.format(title: "Grafana", fields: [SecretField(key: L("Usuário"), value: "admin"),
                                                              SecretField(key: L("Senha"), value: "demo-only-password")])
        guard let from, let env = try? SecretShare.seal(SecretPayload(text: text, kind: .passwords, sender: ana.name),
                                                         from: from, to: me.publicKey) else { return nil }
        return try? write(env, title: "Grafana")
    }

    // MARK: Arquivo

    /// Grava o arquivo numa pasta temporária, pronto para arrastar ou compartilhar.
    /// Os arquivos de antes são apagados: só sobra o último.
    func write(_ env: SecretEnvelope, title: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Menew Share", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        var name = title.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = L("Segredo") }
        let file = dir.appendingPathComponent(String(name.prefix(60))).appendingPathExtension(SecretShare.fileExtension)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(env).write(to: file, options: .atomic)
        return file
    }

    /// "Importar arquivo…": o menu não fecha enquanto o painel está aberto
    func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SecretShare.fileType]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        picking = true
        defer { picking = false }
        return panel.runModal() == .OK ? panel.url : nil
    }
    private(set) var picking = false

    /// Arquivos soltos no notch: os `.menewsecret` vão para a tela de importar, o resto para a estante.
    /// `rest` recebe os itens que não são segredos.
    static func acceptDrop(_ providers: [NSItemProvider], rest: @escaping @MainActor ([NSItemProvider]) -> Void) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { rest(providers); return true }
        let group = DispatchGroup()
        let lock = NSLock()
        var secrets: [Int: URL] = [:]
        for (i, p) in providers.enumerated() where files.contains(p) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                lock.lock()
                if let url, url.pathExtension.lowercased() == SecretShare.fileExtension { secrets[i] = url }
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                if let first = secrets.sorted(by: { $0.key < $1.key }).first?.value {
                    (NSApp.delegate as? AppDelegate)?.importSecret(first)
                }
                let plain = providers.enumerated().filter { secrets[$0.offset] == nil }.map(\.element)
                if !plain.isEmpty { rest(plain) }
            }
        }
        return true
    }
}
