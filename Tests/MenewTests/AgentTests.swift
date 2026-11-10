import XCTest
@testable import Menew

// Agentes de IA: leitura dos registros, preços, limites, hooks e o servidor MCP. Tudo com dados de exemplo.

final class AgentLogTests: XCTestCase {
    private func claudeLine(id: String = "msg_1", req: String = "req_1", model: String = "claude-opus-5-5", content: String = "oi") -> Substring {
        Substring(#"{"type":"assistant","cwd":"/Users/ana/apps/menew","requestId":"\#(req)","timestamp":"2026-11-10T12:00:00.000Z","message":{"id":"\#(id)","model":"\#(model)","content":[{"type":"text","text":"\#(content)"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":2000,"cache_read_input_tokens":50000,"output_tokens":300,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":2000}}}}"#)
    }

    func testClaudeReadsUsageAndDedupes() {
        var seen = Set<String>()
        let r = ClaudeLog.parse(claudeLine(), seen: &seen)
        XCTAssertEqual(r?.model, "claude-opus-5-5")
        XCTAssertEqual(r?.project, "menew")
        XCTAssertEqual(r?.input, 10)
        XCTAssertEqual(r?.output, 300)
        XCTAssertEqual(r?.cacheRead, 50000)
        XCTAssertEqual(r?.cacheWrite1h, 2000)
        XCTAssertEqual(r?.cacheWrite5m, 0)
        // A mesma resposta em outra linha (outro bloco) não conta de novo
        XCTAssertNil(ClaudeLog.parse(claudeLine(), seen: &seen))
        XCTAssertNotNil(ClaudeLog.parse(claudeLine(id: "msg_2"), seen: &seen))
    }

    func testClaudeIgnoresKeysInsideText() {
        var seen = Set<String>()
        // O texto da resposta fala de \"model\":\"x\" (escapado): o modelo continua sendo o de verdade
        let r = ClaudeLog.parse(claudeLine(content: #"veja \"model\":\"fake\" e \"usage\":{}"#), seen: &seen)
        XCTAssertEqual(r?.model, "claude-opus-5-5")
        XCTAssertEqual(r?.output, 300)
    }

    func testClaudeSkipsSyntheticAndUserLines() {
        var seen = Set<String>()
        XCTAssertNil(ClaudeLog.parse(claudeLine(model: "<synthetic>"), seen: &seen))
        XCTAssertNil(ClaudeLog.parse(#"{"type":"user","message":{"content":"oi"}}"#, seen: &seen))
    }

    func testCodexCountsDeltasAndLimits() {
        var log = CodexLog()
        XCTAssertNil(log.parse(#"{"type":"session_meta","payload":{"cwd":"/Users/ana/apps/api"}}"#))
        XCTAssertNil(log.parse(#"{"type":"turn_context","payload":{"model":"gpt-5.5-codex"}}"#))
        let tc = { (input: Int, cached: Int, output: Int) in
            Substring(#"{"timestamp":"2026-11-10T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output)}},"rate_limits":{"primary":{"used_percent":21.5,"window_minutes":300,"resets_at":1795742274},"secondary":{"used_percent":9,"window_minutes":10080,"resets_at":1796000000},"plan_type":"plus"}}}"#)
        }
        let a = log.parse(tc(1000, 800, 50))
        XCTAssertEqual(a?.project, "api")
        XCTAssertEqual(a?.model, "gpt-5.5-codex")
        XCTAssertEqual(a?.input, 200)
        XCTAssertEqual(a?.cacheRead, 800)
        XCTAssertEqual(a?.output, 50)
        // O mesmo total de novo (evento repetido) não gera registro
        XCTAssertNil(log.parse(tc(1000, 800, 50)))
        let b = log.parse(tc(1500, 1200, 80))
        XCTAssertEqual(b?.input, 100)
        XCTAssertEqual(b?.cacheRead, 400)
        XCTAssertEqual(b?.output, 30)
        XCTAssertEqual(log.limits.map(\.usedPercent), [21.5, 9])
        XCTAssertEqual(log.limits.first?.windowMinutes, 300)
        XCTAssertEqual(log.plan, "Plus")
    }

    func testGeminiSession() {
        let json = #"{"messages":[{"type":"user","content":"oi"},{"type":"gemini","timestamp":"2026-11-10T12:00:00Z","model":"gemini-3-pro","tokens":{"input":1000,"output":200,"cached":600,"thoughts":50,"tool":0,"total":1250}}]}"#
        let r = GeminiLog.parse(Data(json.utf8), project: "x")
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.first?.input, 400)
        XCTAssertEqual(r.first?.cacheRead, 600)
        XCTAssertEqual(r.first?.output, 250)
    }
}

final class AgentPricingTests: XCTestCase {
    func testMostSpecificPriceWins() {
        XCTAssertEqual(AgentPricing.price("claude-opus-5-5")?.input, 4)
        XCTAssertEqual(AgentPricing.price("claude-opus-5")?.input, 5)
        XCTAssertEqual(AgentPricing.price("claude-sonnet-5-5")?.cacheRead, 0.1)
        XCTAssertNil(AgentPricing.price("gpt-5.5-codex"))
    }

    func testCostAndSavings() {
        var r = UsageRecord(date: Date(), agent: .claude, model: "claude-opus-5-5", project: "p")
        r.input = 1_000_000; r.output = 1_000_000; r.cacheRead = 1_000_000; r.cacheWrite5m = 1_000_000; r.cacheWrite1h = 1_000_000
        // 4 + 20 + 0,2 + 4×1,25 + 4×2
        XCTAssertEqual(AgentPricing.cost(r)!, 37.2, accuracy: 0.001)
        XCTAssertEqual(AgentPricing.cacheSavings(r), 3.8, accuracy: 0.001)
        r.agent = .codex
        XCTAssertNil(AgentPricing.cost(r))
    }

    func testDisplayName() {
        XCTAssertEqual(AgentPricing.displayName("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(AgentPricing.displayName("claude-haiku-4-5-20251001"), "Haiku 4.5")
        XCTAssertEqual(AgentPricing.displayName("gpt-5.5-codex"), "gpt-5.5-codex")
    }
}

final class RateWindowTests: XCTestCase {
    func testForecastOnlyWhenItRunsOutBeforeReset() {
        let now = Date()
        // Janela de 5 h, 2 h passadas, 60% usado: no ritmo, acaba em 1h20, antes de zerar (3 h)
        let fast = RateWindow(label: "5h", usedPercent: 60, resetsAt: now.addingTimeInterval(3 * 3600), windowMinutes: 300, asOf: now)
        let f = fast.forecast(now: now)
        XCTAssertNotNil(f)
        XCTAssertEqual(f!.timeIntervalSince(now), 4800, accuracy: 1)
        // 20% em 2 h: dá folga
        let slow = RateWindow(label: "5h", usedPercent: 20, resetsAt: now.addingTimeInterval(3 * 3600), windowMinutes: 300, asOf: now)
        XCTAssertNil(slow.forecast(now: now))
    }

    func testClaudeLimitsParse() {
        let json = #"{"five_hour":{"utilization":42,"resets_at":"2026-11-10T15:00:00Z"},"seven_day":{"utilization":10,"resets_at":"2026-11-14T00:00:00Z"},"seven_day_opus":null,"extra":"x"}"#
        let w = ClaudePlanLimits.parse(Data(json.utf8))!
        XCTAssertEqual(w.map(\.usedPercent), [42, 10])
        XCTAssertEqual(w.map(\.windowMinutes), [300, 10080])
        XCTAssertNotNil(w.first?.resetsAt)
    }
}

final class AgentHooksTests: XCTestCase {
    func testInstallKeepsOtherHooksAndUninstallRemovesOnlyOurs() {
        let other: [String: Any] = ["hooks": [["type": "command", "command": "/usr/local/bin/other hook"]]]
        let config: [String: Any] = ["model": "opus", "hooks": ["Stop": [other]]]
        let installed = AgentHooks.updated(config, agent: .claude, install: true)
        XCTAssertEqual(installed["model"] as? String, "opus")
        let hooks = installed["hooks"] as! [String: Any]
        XCTAssertEqual((hooks["Stop"] as! [[String: Any]]).count, 2)
        XCTAssertEqual(Set(hooks.keys), Set(AgentHooks.events(.claude)))
        let cmd = ((hooks["UserPromptSubmit"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]["command"] as! String
        XCTAssertTrue(cmd.contains("--agent-hook claude"))
        // Instalar de novo não duplica
        let twice = AgentHooks.updated(installed, agent: .claude, install: true)
        XCTAssertEqual(((twice["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]).count, 2)
        let removed = AgentHooks.updated(installed, agent: .claude, install: false)
        let left = removed["hooks"] as! [String: Any]
        XCTAssertEqual(Array(left.keys), ["Stop"])
        XCTAssertEqual((left["Stop"] as! [[String: Any]]).count, 1)
    }

    func testGeminiEntriesHaveMatcher() {
        let hooks = AgentHooks.updated([:], agent: .gemini, install: true)["hooks"] as! [String: Any]
        let group = (hooks["AfterAgent"] as! [[String: Any]])[0]
        XCTAssertEqual(group["matcher"] as? String, "*")
    }

    func testProcessListParsing() {
        let ps = """
          101 /Users/ana/.local/bin/claude --resume
          102 /opt/homebrew/bin/codex
          103 /opt/homebrew/bin/codex app-server
          104 node /opt/homebrew/bin/gemini
          105 /Applications/Menew.app/Contents/MacOS/Menew --agent-hook claude
          106 node server.js
        """
        let found = AgentProcesses.parse(ps)
        XCTAssertEqual(found.map(\.1), [101, 102, 104])
        XCTAssertEqual(found.map(\.0), [.claude, .codex, .gemini])
    }
}

@MainActor
final class AgentHubTests: XCTestCase {
    func testStatesFromHookEvents() {
        let hub = AgentHub.shared
        let t0 = Date()
        hub.handle(["agent": "claude", "event": "SessionStart", "session": "s1", "cwd": "/tmp/menew"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "claude.s1" }?.state, .idle)
        hub.handle(["agent": "claude", "event": "UserPromptSubmit", "session": "s1"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "claude.s1" }?.state, .working)
        hub.handle(["agent": "claude", "event": "Notification", "session": "s1", "message": "Claude needs your permission"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "claude.s1" }?.state, .waiting)
        hub.handle(["agent": "claude", "event": "PostToolUse", "session": "s1"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "claude.s1" }?.state, .working)
        hub.handle(["agent": "claude", "event": "Stop", "session": "s1"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "claude.s1" }?.state, .done)
        // O "ainda esperando sua resposta" depois de parado não vira pedido de atenção
        hub.handle(["agent": "claude", "event": "Notification", "session": "s1", "kind": "idle_prompt"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "claude.s1" }?.state, .done)
        hub.handle(["agent": "gemini", "event": "BeforeAgent", "session": "g1"], now: t0)
        XCTAssertEqual(hub.sessions.first { $0.id == "gemini.g1" }?.state, .working)
        hub.handle(["agent": "claude", "event": "SessionEnd", "session": "s1"], now: t0)
        hub.handle(["agent": "gemini", "event": "SessionEnd", "session": "g1"], now: t0)
        XCTAssertNil(hub.sessions.first { $0.id == "claude.s1" })
    }
}

@MainActor
final class MCPServerTests: XCTestCase {
    func testInitializeAndList() {
        let r = MCPServer.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]])
        let result = r?["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-06-18")
        // Notificações não têm resposta
        XCTAssertNil(MCPServer.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        let list = MCPServer.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])?["result"] as? [String: Any]
        let names = (list?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        XCTAssertTrue(names.contains("search_memory"))
        XCTAssertTrue(names.contains("mac_status"))
        let unknown = MCPServer.handle(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "nope"]])
        XCTAssertNotNil(unknown?["error"])
    }
}
