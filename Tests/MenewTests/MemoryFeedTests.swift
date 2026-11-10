import AppKit
import XCTest
@testable import Menew

// Memória automática: segredos, prints copiados, impressão digital das imagens e o resumo das sessões dos agentes.
// Tudo com dados de exemplo.

final class SecretScrubberTests: XCTestCase {
    func testRemovesKnownKeysAndTokens() {
        let s = """
        export ANTHROPIC_API_KEY=sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789
        token ghp_abcdefghijklmnopqrstuvwxyz0123456789 e AKIAABCDEFGHIJKLMNOP
        curl -H "Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456" https://ana:s3nh4@example.com/x
        jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U
        """
        let out = SecretScrubber.scrub(s)
        for leak in ["sk-ant-api03", "ghp_abc", "AKIAABCD", "abcdefghijklmnopqrstuvwxyz123456", "s3nh4", "eyJhbGci"] {
            XCTAssertFalse(out.contains(leak), "vazou \(leak): \(out)")
        }
        // O que não é segredo continua
        XCTAssertTrue(out.contains("export ANTHROPIC_API_KEY="))
        XCTAssertTrue(out.contains("example.com/x"))
    }

    func testRemovesAssignedSecretsButKeepsNames() {
        let out = SecretScrubber.scrub(#"{"password": "hunter2hunter", "db_token": abc123xyz789, "nome": "Ana"}"#)
        XCTAssertFalse(out.contains("hunter2hunter"))
        XCTAssertFalse(out.contains("abc123xyz789"))
        XCTAssertTrue(out.contains(#""password""#))
        XCTAssertTrue(out.contains("Ana"))
    }

    func testRemovesPrivateKeys() {
        let out = SecretScrubber.scrub("antes\n-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAB3NzaC1\n-----END OPENSSH PRIVATE KEY-----\ndepois")
        XCTAssertFalse(out.contains("AAAAB3NzaC1"))
        XCTAssertTrue(out.hasPrefix("antes") && out.hasSuffix("depois"))
    }

    func testLeavesPlainTextAlone() {
        let s = "Rodar swift test e ./build.sh no projeto menew, branch main"
        XCTAssertEqual(SecretScrubber.scrub(s), s)
    }
}

final class ScreenshotFeedTests: XCTestCase {
    func testOnlyImageOnlyPasteboardsLookLikeScreenshots() {
        XCTAssertTrue(MemoryFeed.looksLikeScreenshot(types: ["public.png", "Apple PNG pasteboard type"]))
        XCTAssertTrue(MemoryFeed.looksLikeScreenshot(types: ["public.tiff", "NSTIFFPboardType"]))
        // Uma imagem copiada de uma página vem com HTML e link
        XCTAssertFalse(MemoryFeed.looksLikeScreenshot(types: ["public.tiff", "public.html", "public.url"]))
        // Um arquivo copiado no Finder
        XCTAssertFalse(MemoryFeed.looksLikeScreenshot(types: ["public.file-url", "public.png"]))
        XCTAssertFalse(MemoryFeed.looksLikeScreenshot(types: ["public.utf8-plain-text"]))
    }

    private func image() -> NSImage {
        let img = NSImage(size: NSSize(width: 80, height: 50))
        img.lockFocus()
        NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 80, height: 50).fill()
        NSColor.systemIndigo.setFill(); NSRect(x: 10, y: 10, width: 30, height: 20).fill()
        img.unlockFocus()
        return img
    }

    func testSameImageInPNGAndTIFFHasSameFingerprint() throws {
        let tiff = try XCTUnwrap(image().tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let a = try XCTUnwrap(ImageFingerprint.key(tiff))
        XCTAssertEqual(a, ImageFingerprint.key(png))
        XCTAssertTrue(a.hasPrefix("shot:"))

        let other = NSImage(size: NSSize(width: 80, height: 50))
        other.lockFocus(); NSColor.systemGreen.setFill(); NSRect(x: 0, y: 0, width: 80, height: 50).fill(); other.unlockFocus()
        XCTAssertNotEqual(a, ImageFingerprint.key(try XCTUnwrap(other.tiffRepresentation)))
        XCTAssertNil(ImageFingerprint.key(Data("não é imagem".utf8)))
    }

    func testOldMemoryWithoutSourceKeyStillLoads() throws {
        let json = #"[{"id":"7B0B5C55-6F59-4C5B-9E0B-2C1D1B0F0A11","date":"2026-11-01T10:00:00Z","kind":"text","title":"Oi","summary":"","tags":[],"entities":[],"text":"Oi","enriched":true}]"#
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let items = try dec.decode([MemoryItem].self, from: Data(json.utf8))
        XCTAssertNil(items.first?.sourceKey)
        let session = try dec.decode(MemoryItem.self, from: Data(#"{"id":"7B0B5C55-6F59-4C5B-9E0B-2C1D1B0F0A12","date":"2026-11-01T10:00:00Z","kind":"session","title":"x","summary":"","tags":[],"entities":[],"text":"","enriched":false,"sourceKey":"claude:1"}"#.utf8))
        XCTAssertEqual(session.kind, .session)
        XCTAssertEqual(session.placeholderIcon, "terminal")
    }
}

final class AgentSessionDigestTests: XCTestCase {
    private func lines(_ list: [String], agent: AgentKind) -> AgentSessionDigest {
        var d = AgentSessionDigest(agent: agent)
        for l in list { AgentSessionFeed.feed(Data(l.utf8), into: &d) }
        return d
    }

    func testClaudeSessionSummary() {
        let d = lines([
            #"{"type":"permission-mode","permissionMode":"auto","sessionId":"s1"}"#,
            #"{"type":"user","sessionId":"s1","cwd":"/Users/ana/apps/menew","gitBranch":"main","timestamp":"2026-11-10T12:00:00.000Z","message":{"role":"user","content":"<system-reminder>contexto</system-reminder>Adicionar busca na Memória com a chave sk-ant-api03-abcdefghijklmnopqrstuvwxyz"}}"#,
            #"{"type":"api-request-blob","sessionId":"s1","message":{"content":"não deve ser lido"}}"#,
            #"{"type":"assistant","sessionId":"s1","cwd":"/Users/ana/apps/menew","timestamp":"2026-11-10T12:01:00.000Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/ana/apps/menew/Sources/Menew/Memory.swift"}},{"type":"tool_use","name":"Bash","input":{"command":"cd /Users/ana/apps/menew && swift test"}}]}}"#,
            #"{"type":"user","sessionId":"s1","timestamp":"2026-11-10T12:01:10.000Z","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"assistant","sessionId":"s1","isSidechain":true,"message":{"content":[{"type":"text","text":"resposta do subagente"}]}}"#,
            #"{"type":"assistant","sessionId":"s1","timestamp":"2026-11-10T12:05:00.000Z","message":{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"Pronto: busca adicionada e testes passando."}]}}"#,
            #"{"type":"ai-title","aiTitle":"Busca na Memória","sessionId":"s1"}"#,
            #"{"type":"user","sessionId":"s1","message":{"content":"<command-name>/clear</command-name>"}}"#,
        ], agent: .claude)

        XCTAssertEqual(d.sourceKey, "claude:s1")
        XCTAssertEqual(d.project, "menew")
        XCTAssertEqual(d.branch, "main")
        XCTAssertEqual(d.title, "Busca na Memória")
        XCTAssertEqual(d.prompts.count, 1)
        XCTAssertEqual(d.files, ["Sources/Menew/Memory.swift"])
        XCTAssertEqual(d.commands, ["swift test"])
        XCTAssertEqual(d.lastReply, "Pronto: busca adicionada e testes passando.")
        XCTAssertEqual(d.end.map { Int($0.timeIntervalSince(d.start!)) }, 300)
        XCTAssertTrue(d.isWorthKeeping)

        let text = d.text
        XCTAssertTrue(text.contains("Adicionar busca na Memória"))
        XCTAssertTrue(text.contains("Sources/Menew/Memory.swift"))
        XCTAssertFalse(text.contains("sk-ant-api03"), text)
        XCTAssertFalse(text.contains("contexto"))
        XCTAssertFalse(text.contains("subagente"))
        XCTAssertFalse(text.contains("não deve ser lido"))
    }

    func testClaudeWithoutReplyIsNotKept() {
        let d = lines([#"{"type":"user","sessionId":"s2","message":{"content":"oi"}}"#], agent: .claude)
        XCTAssertFalse(d.isWorthKeeping)
        XCTAssertEqual(d.title, "oi")
    }

    func testCodexSessionSummary() {
        let d = lines([
            #"{"timestamp":"2026-11-10T09:00:00.000Z","type":"session_meta","payload":{"id":"c1","cwd":"/Users/ana/apps/api","git":{"branch":"feat/x"}}}"#,
            #"{"timestamp":"2026-11-10T09:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>cwd</environment_context>"}]}}"#,
            #"{"timestamp":"2026-11-10T09:00:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Corrigir o login"}]}}"#,
            #"{"timestamp":"2026-11-10T09:00:02.000Z","type":"event_msg","payload":{"type":"user_message","message":"Corrigir o login"}}"#,
            #"{"timestamp":"2026-11-10T09:01:00.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch\n*** Update File: src/auth.ts\n@@\n*** Add File: src/auth.test.ts\n*** End Patch"}}"#,
            #"{"timestamp":"2026-11-10T09:02:00.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"npm test\"}"}}"#,
            #"{"timestamp":"2026-11-10T09:03:00.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Login corrigido."}]}}"#,
        ], agent: .codex)

        XCTAssertEqual(d.sourceKey, "codex:c1")
        XCTAssertEqual(d.project, "api")
        XCTAssertEqual(d.branch, "feat/x")
        XCTAssertEqual(d.prompts, ["Corrigir o login"])
        XCTAssertEqual(d.files, ["src/auth.ts", "src/auth.test.ts"])
        XCTAssertEqual(d.commands, ["npm test"])
        XCTAssertEqual(d.lastReply, "Login corrigido.")
        XCTAssertEqual(d.title, "Corrigir o login")
    }

    func testGeminiSessionSummary() throws {
        let json = #"{"sessionId":"g1","startTime":"2026-11-10T08:00:00.000Z","messages":[{"type":"user","content":"Explique o build","timestamp":"2026-11-10T08:00:00.000Z"},{"type":"gemini","content":"O build usa SwiftPM.","timestamp":"2026-11-10T08:00:30.000Z","toolCalls":[{"name":"run_shell_command","args":{"command":"swift build"}},{"name":"write_file","args":{"file_path":"notes.md"}}]}]}"#
        let d = try XCTUnwrap(AgentSessionDigest.gemini(Data(json.utf8)))
        XCTAssertEqual(d.sourceKey, "gemini:g1")
        XCTAssertEqual(d.prompts, ["Explique o build"])
        XCTAssertEqual(d.commands, ["swift build"])
        XCTAssertEqual(d.files, ["notes.md"])
        XCTAssertTrue(d.isWorthKeeping)
    }
}
