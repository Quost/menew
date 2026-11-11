import XCTest
@testable import Menew

// As outras ferramentas de IA: cada formato com um arquivo de exemplo (os nomes dos campos vêm do código de cada uma),
// os hooks de cada uma e a lista de processos.

final class AgentSourcesTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("menew-sources-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func write(_ name: String, _ text: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testOpenCodeMessageWithReportedCost() {
        let url = write("msg_1.json", #"""
        {"id":"msg_1","sessionID":"ses_1","role":"assistant","modelID":"claude-sonnet-5-5","providerID":"anthropic","cost":0.0123,
         "tokens":{"input":120,"output":300,"reasoning":50,"cache":{"read":4000,"write":200}},"time":{"created":1794000000000},
         "path":{"root":"/Users/ana/apps/menew"}}
        """#)
        let r = OpenCodeLog.parse(url)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].agent, .opencode)
        XCTAssertEqual(r[0].input, 120)
        XCTAssertEqual(r[0].output, 350)
        XCTAssertEqual(r[0].cacheRead, 4000)
        XCTAssertEqual(r[0].cacheWrite5m, 200)
        XCTAssertEqual(r[0].project, "menew")
        XCTAssertEqual(AgentPricing.cost(r[0]) ?? 0, 0.0123, accuracy: 0.00001)
        XCTAssertEqual(r[0].key, "opencode:msg_1")
        // As mensagens do usuário não contam
        XCTAssertTrue(OpenCodeLog.record(["role": "user", "tokens": [:], "time": ["created": 1]], directory: nil) == nil)
    }

    func testKiroCountsCreditsPerTurn() {
        _ = write("ws/sess_1/session.json", #"{"id":"sess_1","modelId":"auto","workspacePaths":["/Users/ana/apps/api"]}"#)
        let url = write("ws/sess_1/messages.jsonl", """
        {"id":"1","timestamp":"2026-11-06T13:24:19.435Z","payload":{"type":"usage_summary","promptTurnSummaries":[{"unit":"credit","unitPlural":"credits","usage":1.5,"usedTools":["read_file"]}]}}
        {"id":"2","timestamp":"2026-11-06T13:25:00.000Z","payload":{"type":"assistant","content":"oi"}}
        {"id":"3","timestamp":"2026-11-06T13:30:00.000Z","payload":{"type":"usage_summary","promptTurnSummaries":[{"unit":"credit","usage":0.5},{"unit":"credit","usage":0.25}]}}
        """)
        let r = KiroLog.parse(url)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r.map(\.credits), [1.5, 0.75])
        XCTAssertEqual(r[0].project, "api")
        XCTAssertEqual(r[0].model, "Kiro Auto")
        XCTAssertEqual(r[0].client, .ide)
        XCTAssertEqual(AgentPricing.cost(r[0]) ?? 0, 1.5 * KiroLog.creditPrice, accuracy: 0.0001)
    }

    func testKiroCLITurns() {
        let url = write("cli/abc.json", #"""
        {"session_id":"abc","cwd":"/Users/ana/apps/site","session_state":{"rts_model_state":{"model_info":{"model_id":"claude-sonnet-5"}},
         "conversation_metadata":{"user_turn_metadatas":[{"input_token_count":100,"output_token_count":40,"cache_read_input_token_count":900,
         "cache_write_input_token_count":10,"end_timestamp":"2026-11-06T10:00:00Z","metering_usage":[{"value":0.8,"unit":"credit"}]}]}}}
        """#)
        let r = KiroLog.parse(url)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].total, 1050)
        XCTAssertEqual(r[0].credits, 0.8, accuracy: 0.0001)
        XCTAssertEqual(r[0].project, "site")
    }

    func testQwenSplitsCacheAndThoughts() {
        let url = write("-Users-ana-apps-menew/chats/s.jsonl", """
        {"type":"user","timestamp":"2026-11-06T10:00:00Z"}
        {"type":"assistant","model":"qwen3-coder","timestamp":"2026-11-06T10:00:05Z","sessionId":"s","usageMetadata":{"promptTokenCount":1000,"candidatesTokenCount":200,"thoughtsTokenCount":50,"cachedContentTokenCount":600,"totalTokenCount":1250}}
        """)
        let r = QwenLog.parse(url)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].input, 400)
        XCTAssertEqual(r[0].cacheRead, 600)
        XCTAssertEqual(r[0].output, 250)
        XCTAssertEqual(r[0].project, "menew")
    }

    func testAmpMessagesWithCredits() {
        let url = write("T-1.json", #"""
        {"id":"T-1","created":1794000000000,"messages":[{"role":"user"},{"role":"assistant","messageId":2,
         "usage":{"model":"claude-sonnet-5-5","inputTokens":10,"outputTokens":500,"cacheReadInputTokens":9000,"cacheCreationInputTokens":300,"credits":0.21,"timestamp":"2026-11-06T10:00:00Z"}}]}
        """#)
        let r = AmpLog.parse(url)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].total, 9810)
        XCTAssertEqual(r[0].credits, 0.21, accuracy: 0.0001)
    }

    func testOpenClawAssistantUsage() {
        let url = write("s1.jsonl", """
        {"type":"message","id":"e1","message":{"role":"user","content":"oi"}}
        {"type":"message","id":"e2","message":{"role":"assistant","model":"claude-opus-5-5","timestamp":1794000000000,"usage":{"input":20,"output":80,"cacheRead":1000,"cacheWrite":0,"cost":{"total":0.004}}}}
        """)
        let r = OpenClawLog.parse(url)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].total, 1100)
        XCTAssertEqual(r[0].reportedCost ?? 0, 0.004, accuracy: 0.00001)
        XCTAssertNotNil(r[0].key)
    }

    func testKimiKeepsTheLargestSnapshotOfAMessage() {
        let url = write("g/s/wire.jsonl", """
        {"timestamp":1794000000.5,"message":{"type":"StatusUpdate","payload":{"message_id":"m1","token_usage":{"input_other":100,"output":10,"input_cache_read":0,"input_cache_creation":0}}}}
        {"timestamp":1794000001.5,"message":{"type":"StatusUpdate","payload":{"message_id":"m1","token_usage":{"input_other":100,"output":60,"input_cache_read":500,"input_cache_creation":0}}}}
        """)
        let r = KimiLog.parseCLI(url)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].total, 660)
    }

    func testDroidSessionTotals() {
        let url = write("-Users-ana-apps-api/abc.settings.json", #"""
        {"model":"claude-opus-5-5","providerLockTimestamp":"2026-11-06T09:00:00Z","tokenUsage":{"inputTokens":300,"outputTokens":700,"cacheCreationTokens":100,"cacheReadTokens":5000,"thinkingTokens":50}}
        """#)
        let r = DroidLog.parse(url)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].output, 750)
        XCTAssertEqual(r[0].project, "api")
    }

    func testDatesInEveryShape() {
        let d = Date(timeIntervalSince1970: 1_794_000_000)
        XCTAssertEqual(AgentFiles.date(1_794_000_000_000.0), d)
        XCTAssertEqual(AgentFiles.date(1_794_000_000), d)
        XCTAssertEqual(AgentFiles.date("2026-11-06T10:00:00Z"), AgentDates.parse("2026-11-06T10:00:00Z"))
        XCTAssertNotNil(AgentFiles.date("2026-11-06 10:00:00"))
        XCTAssertNil(AgentFiles.date("ontem"))
    }

    func testDuplicatesAcrossFormatsCountOnce() {
        // O OpenCode guarda a mesma resposta no formato antigo e no banco novo: o scanner fica com uma
        var keys = Set<String>()
        let a = UsageRecord(date: Date(), agent: .opencode, model: "m", project: "p", input: 1, key: "opencode:1")
        let list = [a, a, UsageRecord(date: Date(), agent: .opencode, model: "m", project: "p", input: 1)]
        XCTAssertEqual(list.filter { r in r.key.map { keys.insert($0).inserted } ?? true }.count, 2)
    }
}

final class AgentHookStylesTests: XCTestCase {
    func testCursorFlatHooksKeepOthers() {
        let config: [String: Any] = ["version": 1, "hooks": ["stop": [["command": "./hooks/audit.sh"]]]]
        let on = AgentHooks.updated(config, agent: .cursor, install: true)
        let hooks = on["hooks"] as! [String: Any]
        let stop = hooks["stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2)
        XCTAssertTrue((stop[1]["command"] as! String).hasSuffix("--agent-hook cursor stop"))
        XCTAssertNotNil(hooks["beforeSubmitPrompt"])
        // Nada de evento que decide se a ferramenta roda
        XCTAssertNil(hooks["preToolUse"])
        let off = AgentHooks.updated(on, agent: .cursor, install: false)
        XCTAssertEqual(((off["hooks"] as! [String: Any])["stop"] as! [[String: Any]]).count, 1)
        XCTAssertEqual((off["hooks"] as! [String: Any]).count, 1)
    }

    func testCopilotAndKiroGetTheirOwnFile() {
        let copilot = AgentHooks.updated([:], agent: .copilot, install: true)
        XCTAssertEqual(copilot["version"] as? Int, 1)
        let stop = ((copilot["hooks"] as! [String: Any])["agentStop"] as! [[String: Any]])[0]
        XCTAssertEqual(stop["type"] as? String, "command")
        XCTAssertTrue((stop["bash"] as! String).hasSuffix("--agent-hook copilot agentStop"))
        XCTAssertEqual(AgentHooks.configURL(.copilot).lastPathComponent, "menew.json")

        let kiro = AgentHooks.updated([:], agent: .kiro, install: true)
        XCTAssertEqual(kiro["version"] as? String, "v1")
        let list = kiro["hooks"] as! [[String: Any]]
        XCTAssertEqual(list.map { $0["trigger"] as! String }, AgentHooks.events(.kiro))
        XCTAssertTrue(((list[0]["action"] as! [String: Any])["command"] as! String).contains("--agent-hook kiro SessionStart"))
        XCTAssertEqual(AgentHooks.ourCommands(kiro).count, AgentHooks.events(.kiro).count)
        XCTAssertTrue(AgentHooks.updated(kiro, agent: .kiro, install: false).isEmpty)
    }

    func testQwenAndDroidUseClaudeShape() {
        for a in [AgentKind.qwen, .droid] {
            let on = AgentHooks.updated(["model": "x"], agent: a, install: true)
            XCTAssertEqual(on["model"] as? String, "x")
            let groups = (on["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
            XCTAssertEqual(((groups[0]["hooks"] as! [[String: Any]])[0]["command"] as! String), AgentHooks.command(a))
        }
        XCTAssertNotNil((AgentHooks.updated([:], agent: .qwen, install: true)["hooks"] as! [String: Any])["PermissionRequest"])
    }

    func testAgentsWithoutHooks() {
        for a in [AgentKind.opencode, .amp, .openclaw, .kimi, .goose] {
            XCTAssertFalse(a.hasHooks)
            XCTAssertTrue(AgentHooks.events(a).isEmpty)
            XCTAssertEqual(AgentHooks.status(a), .notInstalled)
        }
    }

    func testStepFromOtherPayloads() {
        // Copilot: camelCase e argumentos em texto
        let c = AgentHookCommand.step(["toolName": "bash", "toolArgs": #"{"command":"npm test"}"#])
        XCTAssertEqual(c?.tool, "bash")
        XCTAssertEqual(c?.detail, "npm test")
        // Cursor: o comando e o arquivo vêm direto no evento
        XCTAssertEqual(AgentHookCommand.step(["command": "swift build"])?.detail, "swift build")
        XCTAssertEqual(AgentHookCommand.step(["file_path": "/a/b/View.swift"])?.detail, "View.swift")
    }

    func testProcessesOfOtherAgents() {
        let ps = """
          10 opencode
          11 /Users/ana/.local/bin/kiro-cli chat
          12 node /opt/homebrew/lib/node_modules/@github/copilot/index.js
          13 droid
          14 node /opt/homebrew/bin/qwen
          15 opencode serve --port 4096
          16 openclaw gateway
          17 /Users/ana/.local/bin/cursor-agent
          18 goose session
        """
        let found = Dictionary(uniqueKeysWithValues: AgentProcesses.parse(ps).map { ($0.1, $0.0) })
        XCTAssertEqual(found[10], .opencode)
        XCTAssertEqual(found[11], .kiro)
        XCTAssertEqual(found[12], .copilot)
        XCTAssertEqual(found[13], .droid)
        XCTAssertEqual(found[14], .qwen)
        XCTAssertNil(found[15])
        XCTAssertNil(found[16])
        XCTAssertEqual(found[17], .cursor)
        XCTAssertEqual(found[18], .goose)
    }
}

@MainActor
final class OtherAgentEventsTests: XCTestCase {
    func testCursorAndCopilotEventNames() {
        let hub = AgentHub.shared
        let t0 = Date()
        hub.handle(["agent": "cursor", "event": "beforeSubmitPrompt", "session": "c1", "prompt": "Fix the build"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "cursor.c1" }?.state, .working)
        hub.handle(["agent": "cursor", "event": "afterShellExecution", "session": "c1", "tool": "Bash", "detail": "npm test"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "cursor.c1" }?.detail, "npm test")
        hub.handle(["agent": "cursor", "event": "stop", "session": "c1"], now: t0.addingTimeInterval(5))
        XCTAssertEqual(hub.sessions.first { $0.id == "cursor.c1" }?.state, .done)

        hub.handle(["agent": "copilot", "event": "userPromptSubmitted", "session": "p1"], now: t0)
        hub.handle(["agent": "copilot", "event": "notification", "session": "p1", "kind": "permission_prompt", "message": "Allow bash?"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "copilot.p1" }?.state, .waiting)
        hub.handle(["agent": "copilot", "event": "agentStop", "session": "p1"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "copilot.p1" }?.state, .done)
        hub.handle(["agent": "copilot", "event": "sessionEnd", "session": "p1"], now: t0)
        XCTAssertNil(hub.sessions.first { $0.id == "copilot.p1" })
        hub.handle(["agent": "cursor", "event": "sessionEnd", "session": "c1"], now: t0)
    }
}
