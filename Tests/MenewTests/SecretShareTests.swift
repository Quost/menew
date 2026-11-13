import CryptoKit
import XCTest
@testable import Menew

// Compartilhar senhas: o arquivo abre só com a chave certa ou a senha certa, e qualquer alteração é recusada.

final class SecretShareTests: XCTestCase {
    private let payload = SecretPayload(text: "Grafana\nUsuário: admin\nSenha: s3cr:et", kind: .passwords, sender: "Ana")

    private func roundTrip(_ env: SecretEnvelope) throws -> SecretEnvelope {
        try SecretShare.decode(try JSONEncoder().encode(env))
    }

    func testContactModeOpensOnlyForTheRecipient() throws {
        let ana = Curve25519.KeyAgreement.PrivateKey(), bruno = Curve25519.KeyAgreement.PrivateKey()
        let env = try roundTrip(try SecretShare.seal(payload, from: ana, to: bruno.publicKey))
        let (secret, sender) = try SecretShare.open(env, with: bruno)
        XCTAssertEqual(secret.text, payload.text)
        XCTAssertEqual(secret.fieldNames, ["Usuário", "Senha"])
        XCTAssertEqual(sender.rawRepresentation, ana.publicKey.rawRepresentation)
        XCTAssertThrowsError(try SecretShare.open(env, with: Curve25519.KeyAgreement.PrivateKey())) {
            XCTAssertEqual($0 as? SecretShareError, .notForMe)
        }
    }

    func testContactModeRejectsAForgedSender() throws {
        let ana = Curve25519.KeyAgreement.PrivateKey(), bruno = Curve25519.KeyAgreement.PrivateKey()
        var env = try SecretShare.seal(payload, from: ana, to: bruno.publicKey)
        // Trocar o remetente por outra chave não passa: a chave derivada muda e o cabeçalho é autenticado
        env.from = SecretShare.base64url(Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        XCTAssertThrowsError(try SecretShare.open(env, with: bruno)) { XCTAssertEqual($0 as? SecretShareError, .damaged) }
    }

    func testPassphraseModeIgnoresCaseSpacesAndDashes() throws {
        let pass = SecretShare.generatePassphrase()
        XCTAssertEqual(pass.count, 19)
        XCTAssertTrue(pass.allSatisfy { "abcdefghjkmnpqrstuvwxyz23456789-".contains($0) })
        let env = try roundTrip(try SecretShare.seal(payload, passphrase: pass, rounds: 20_000))
        let typed = pass.uppercased().replacingOccurrences(of: "-", with: " ")
        XCTAssertEqual(try SecretShare.open(env, passphrase: typed).text, payload.text)
        XCTAssertThrowsError(try SecretShare.open(env, passphrase: "aaaa-bbbb-cccc-dddd")) {
            XCTAssertEqual($0 as? SecretShareError, .wrongPassphrase)
        }
    }

    func testTamperedHeaderIsRefused() throws {
        var env = try SecretShare.seal(payload, passphrase: "abcd-efgh-jkmn-pqrs", rounds: 20_000)
        env.rounds = 30_000
        XCTAssertThrowsError(try SecretShare.open(env, passphrase: "abcd-efgh-jkmn-pqrs"))
    }

    func testDecodeRejectsOtherFiles() {
        XCTAssertThrowsError(try SecretShare.decode(Data("{\"a\":1}".utf8))) { XCTAssertEqual($0 as? SecretShareError, .notASecret) }
        let newer = Data(#"{"menew":"secret","v":2,"mode":"contact","box":""}"#.utf8)
        XCTAssertThrowsError(try SecretShare.decode(newer)) { XCTAssertEqual($0 as? SecretShareError, .newerVersion) }
    }

    func testParseCodeKeepsTheNameThatCameWithIt() throws {
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey
        let code = SecretShare.code(for: key)
        let parsed = try XCTUnwrap(SecretShare.parseCode("Ana Souza · \(code)"))
        XCTAssertEqual(parsed.key.rawRepresentation, key.rawRepresentation)
        XCTAssertEqual(parsed.name, "Ana Souza")
        XCTAssertEqual(SecretShare.parseCode(code)?.name, "")
        XCTAssertNil(SecretShare.parseCode("menew-key:curto"))
        XCTAssertEqual(SecretShare.fingerprint(key.rawRepresentation).count, 14)
    }
}
