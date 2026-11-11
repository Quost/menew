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
    func testWindowThatAlreadyResetShowsZeroAndTheNextReset() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Lida às 9h com 80%, zerava às 10h; agora são 17h30: já passaram uma janela e meia de 5 h
        let old = RateWindow(label: "5h", usedPercent: 80, resetsAt: now.addingTimeInterval(-7.5 * 3600), windowMinutes: 300, asOf: now.addingTimeInterval(-8.5 * 3600))
        let w = old.rolled(now: now)
        XCTAssertEqual(w.usedPercent, 0)
        XCTAssertEqual(w.resetsAt, now.addingTimeInterval(2.5 * 3600))
        // Sem saber a duração, zera e não inventa o próximo reset
        var unknown = old; unknown.windowMinutes = nil
        XCTAssertEqual(unknown.rolled(now: now).usedPercent, 0)
        XCTAssertNil(unknown.rolled(now: now).resetsAt)
        // Ainda dentro da janela: igual
        let live = RateWindow(label: "5h", usedPercent: 40, resetsAt: now.addingTimeInterval(3600), windowMinutes: 300, asOf: now)
        XCTAssertEqual(live.rolled(now: now), live)
    }

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

    func testProjectionWithRecentPace() {
        let now = Date()
        let w = RateWindow(label: "5h", usedPercent: 60, resetsAt: now.addingTimeInterval(2 * 3600), windowMinutes: 300, asOf: now)
        // 30 pontos por hora: os 40 que faltam acabam em 80 min, antes de zerar (2 h)
        let fast = w.projection(pace: 30.0 / 3600, now: now)
        XCTAssertEqual(fast?.runsOut?.timeIntervalSince(now) ?? 0, 4800, accuracy: 1)
        XCTAssertEqual(fast?.perHour ?? 0, 30, accuracy: 0.001)
        // 5 pontos por hora: chega a 70% quando zerar
        let slow = w.projection(pace: 5.0 / 3600, now: now)
        XCTAssertNil(slow?.runsOut)
        if case .reaches(let p)? = slow?.kind { XCTAssertEqual(p, 70, accuracy: 0.01) } else { XCTFail() }
        XCTAssertNil(RateWindow(label: "x", usedPercent: 100, resetsAt: now.addingTimeInterval(60), windowMinutes: 300, asOf: now).projection(pace: 1))
    }

    func testRecentPace() {
        let now = Date()
        XCTAssertNil(AgentUsageStore.pace([(now.addingTimeInterval(-300), 10), (now, 12)], now: now))   // menos de 10 min
        let p = AgentUsageStore.pace([(now.addingTimeInterval(-5000), 0), (now.addingTimeInterval(-1800), 40), (now, 46)], now: now)
        XCTAssertEqual(p! * 3600, 12, accuracy: 0.01)   // só a última hora conta: 6 pontos em 30 min
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

    func testStepFromHook() {
        let e = AgentHookCommand.step(["tool_name": "Edit", "tool_input": ["file_path": "/a/b/AgentsView.swift"]])
        XCTAssertEqual(e?.tool, "Edit")
        XCTAssertEqual(e?.detail, "AgentsView.swift")
        XCTAssertEqual(AgentHookCommand.step(["tool_name": "Bash", "tool_input": ["command": "swift test\nmore", "description": "Run the tests"]])?.detail, "Run the tests")
        XCTAssertEqual(AgentHookCommand.step(["tool_name": "shell", "tool_input": ["command": ["bash", "-lc", "npm test"]]])?.detail, "npm test")
        XCTAssertNil(AgentHookCommand.step([:]))
    }

    func testStepText() {
        XCTAssertEqual(AgentStep.clean("cd /private/tmp/x && FOO=1 /usr/bin/git commit -m x"), "git commit -m x")
        XCTAssertEqual(AgentStep.clean("cd a && cd b"), "cd b")
        XCTAssertEqual(AgentStep.text(tool: "Bash", detail: "cd /tmp/x && swift test"), L("Rodando") + " swift test")
        XCTAssertEqual(AgentStep.text(tool: "Edit", detail: "Notch.swift"), L("Editando") + " Notch.swift")
        XCTAssertEqual(AgentStep.text(tool: "mcp__menew__search_notes", detail: nil), "menew: search_notes")
        XCTAssertEqual(AgentStep.duration(252), "4 min 12 s")
        XCTAssertEqual(AgentStep.duration(40), "40 s")
        XCTAssertEqual(AgentStep.task("<agent-message from=\"a99\">\nRebase docs onto develop\n</agent-message>"), "Rebase docs onto develop")
        XCTAssertEqual(AgentStep.task("<command-name>/review</command-name>\n<command-args>PR 12</command-args>"), "/review")
        XCTAssertEqual(AgentStep.task("Fix the a < b check"), "Fix the a < b check")
        XCTAssertNil(AgentStep.task("<system-reminder></system-reminder>"))
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

final class AgentClientTests: XCTestCase {
    func testClaudeEntrypoint() {
        XCTAssertEqual(AgentClient.claude(entrypoint: "cli"), .cli)
        XCTAssertEqual(AgentClient.claude(entrypoint: "claude-desktop"), .desktop)
        XCTAssertEqual(AgentClient.claude(entrypoint: "claude-vscode"), .ide)
        XCTAssertEqual(AgentClient.claude(entrypoint: "sdk-ts"), .sdk)
        XCTAssertEqual(AgentClient.claude(entrypoint: nil), .cli)
    }

    func testCodexOriginator() {
        XCTAssertEqual(AgentClient.codex(originator: "codex-tui", source: "vscode"), .cli)
        XCTAssertEqual(AgentClient.codex(originator: "codex_cli_rs", source: nil), .cli)
        XCTAssertEqual(AgentClient.codex(originator: "codex_work_desktop", source: "vscode"), .desktop)
        XCTAssertEqual(AgentClient.codex(originator: "Codex Desktop", source: nil), .desktop)
        XCTAssertEqual(AgentClient.codex(originator: "codex_vscode", source: "vscode"), .ide)
        XCTAssertEqual(AgentClient.codex(originator: nil, source: "cli"), .cli)
    }

    func testParsersReadClient() {
        var seen = Set<String>()
        let line = Substring(#"{"type":"assistant","entrypoint":"claude-desktop","cwd":"/a/menew","requestId":"r","timestamp":"2026-11-10T12:00:00Z","message":{"id":"msg_9","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":5}}}"#)
        XCTAssertEqual(ClaudeLog.parse(line, seen: &seen)?.client, .desktop)
        var log = CodexLog()
        _ = log.parse(#"{"type":"session_meta","payload":{"cwd":"/a/api","originator":"codex_work_desktop","source":"vscode"}}"#)
        let r = log.parse(#"{"timestamp":"2026-11-10T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}}"#)
        XCTAssertEqual(r?.client, .desktop)
    }
}

final class AgentHistoryTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        c.firstWeekday = 2   // semana começa na segunda
        return c
    }()

    private func date(_ s: String, hour: Int = 12) -> Date {
        let p = s.split(separator: "-").map { Int($0)! }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
    }

    private func rec(_ day: String, hour: Int = 12, agent: AgentKind = .claude, client: AgentClient = .cli, model: String = "claude-opus-5-5",
                     project: String = "menew", output: Int = 100) -> UsageRecord {
        var r = UsageRecord(date: date(day, hour: hour), agent: agent, model: model, project: project, client: client)
        r.input = 10
        r.output = output
        r.cacheRead = 1000
        r.cacheWrite1h = 50
        return r
    }

    func testAggregateSumsPerDayToolClientModelProject() {
        let rows = AgentUsageHistory.aggregate([
            rec("2026-11-10", hour: 9), rec("2026-11-10", hour: 18), rec("2026-11-10", client: .desktop),
            rec("2026-11-11"), rec("2026-11-10", agent: .codex, model: "gpt-5.5-codex"),
        ], calendar: cal)
        XCTAssertEqual(rows.count, 4)
        let cli = rows.first { $0.day == "2026-11-10" && $0.agent == .claude && $0.client == .cli }!
        XCTAssertEqual(cli.replies, 2)
        XCTAssertEqual(cli.output, 200)
        XCTAssertEqual(cli.cacheWrite, 100)
        XCTAssertEqual(cli.total, 2 * (10 + 100 + 1000 + 50))
        // Custo da Opus 5.5: (10×4 + 100×20 + 1000×0,2 + 50×8) / 1 M, por resposta
        XCTAssertEqual(cli.cost, 2 * 0.00264, accuracy: 1e-9)
        XCTAssertEqual(rows.first { $0.agent == .codex }?.cost, 0)
    }

    func testDaysFollowTheLocalTimeZone() {
        // 23:30 em São Paulo já é o dia seguinte em UTC; conta no dia local
        let rows = AgentUsageHistory.aggregate([rec("2026-11-10", hour: 23)], calendar: cal)
        XCTAssertEqual(rows.map(\.day), ["2026-11-10"])
    }

    func testRescanDoesNotDoubleCount() {
        var h = AgentUsageHistory()
        let scan = [rec("2026-11-09"), rec("2026-11-10"), rec("2026-11-11")]
        XCTAssertTrue(h.merge(scan, coveredFrom: date("2026-11-09", hour: 0), calendar: cal))
        let once = h.rows
        // A mesma leitura de novo (o timer de 2 minutos) não muda nada
        XCTAssertFalse(h.merge(scan, coveredFrom: date("2026-11-09", hour: 0), calendar: cal))
        XCTAssertEqual(h.rows, once)
        // Mais respostas hoje: o dia é trocado, não somado
        XCTAssertTrue(h.merge(scan + [rec("2026-11-11", hour: 15)], coveredFrom: date("2026-11-09", hour: 0), calendar: cal))
        XCTAssertEqual(h.rows.first { $0.day == "2026-11-11" }?.replies, 2)
        XCTAssertEqual(h.rows.reduce(0) { $0 + $1.replies }, 4)
    }

    func testDaysBeforeTheScanWindowAreKept() {
        var h = AgentUsageHistory()
        h.merge([rec("2026-08-01"), rec("2026-11-01")], coveredFrom: .distantPast, calendar: cal)
        // A leitura seguinte só cobre novembro em diante: agosto fica como estava
        h.merge([rec("2026-11-01"), rec("2026-11-10")], coveredFrom: date("2026-11-01", hour: 0), calendar: cal)
        XCTAssertEqual(h.rows.map(\.day), ["2026-08-01", "2026-11-01", "2026-11-10"])
        // Um registro de antes da janela que ainda veio na leitura não conta (pode estar pela metade)
        h.merge([rec("2026-10-31"), rec("2026-11-10")], coveredFrom: date("2026-11-01", hour: 0), calendar: cal)
        XCTAssertNil(h.rows.first { $0.day == "2026-10-31" })
    }

    func testDeletedLogsDoNotShrinkADay() {
        var h = AgentUsageHistory()
        h.merge([rec("2026-11-05"), rec("2026-11-05", hour: 14), rec("2026-11-05", agent: .codex, model: "gpt-5.5-codex")],
                coveredFrom: date("2026-11-01", hour: 0), calendar: cal)
        // O Claude Code apagou uma conversa antiga: o dia do Claude encolheria, então fica o guardado
        h.merge([rec("2026-11-05"), rec("2026-11-05", agent: .codex, model: "gpt-5.5-codex", output: 400)],
                coveredFrom: date("2026-11-01", hour: 0), calendar: cal)
        XCTAssertEqual(h.rows.first { $0.agent == .claude }?.replies, 2)
        // O do Codex cresceu: troca
        XCTAssertEqual(h.rows.first { $0.agent == .codex }?.output, 400)
    }

    func testSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("menew-test-\(UUID().uuidString)/agent-usage.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var h = AgentUsageHistory(backfilled: true)
        h.merge([rec("2026-11-10", client: .desktop)], coveredFrom: .distantPast, calendar: cal)
        h.save(to: url)
        XCTAssertEqual(AgentUsageHistory.load(from: url), h)
        XCTAssertEqual(AgentUsageHistory.load(from: url.appendingPathExtension("missing")), AgentUsageHistory())
    }

    func testBucketsByRange() {
        XCTAssertEqual(UsageBucket.forSpan(days: 7), .day)
        XCTAssertEqual(UsageBucket.forSpan(days: 90), .day)
        XCTAssertEqual(UsageBucket.forSpan(days: 365), .week)
        XCTAssertEqual(UsageBucket.forSpan(days: 800), .month)
        // Quarta, 11 de novembro de 2026: a semana começa na segunda (9), o mês no dia 1
        XCTAssertEqual(UsageBucket.week.start(of: date("2026-11-11"), cal), date("2026-11-09", hour: 0))
        XCTAssertEqual(UsageBucket.month.start(of: date("2026-11-11"), cal), date("2026-11-01", hour: 0))
        XCTAssertEqual(UsageBucket.day.start(of: date("2026-11-11"), cal), date("2026-11-11", hour: 0))
    }

    func testWindowsAndBars() {
        var h = AgentUsageHistory()
        h.merge([rec("2025-06-15"), rec("2026-11-02"), rec("2026-11-03", agent: .codex, model: "gpt-5.5-codex"), rec("2026-11-11")],
                coveredFrom: .distantPast, calendar: cal)
        let now = date("2026-11-11", hour: 15)

        let week = h.window(.week, now: now, calendar: cal)
        XCTAssertEqual(week, UsageWindow(start: date("2026-11-05", hour: 0), bucket: .day))
        XCTAssertEqual(h.bars(week, byAgent: false, now: now, calendar: cal).count, 7)

        // 12 meses: uma barra por semana, começando numa segunda
        let year = h.window(.year, now: now, calendar: cal)
        XCTAssertEqual(year.bucket, .week)
        XCTAssertEqual(cal.component(.weekday, from: year.start), 2)
        let weekly = h.bars(year, byAgent: false, now: now, calendar: cal)
        XCTAssertEqual(weekly.count, 53)
        // 2 e 3 de novembro caem na mesma semana; o 11 na seguinte
        XCTAssertEqual(weekly.first { $0.start == date("2026-11-02", hour: 0) }?.tokens, 2 * 1160)
        XCTAssertEqual(weekly.last?.tokens, 1160)
        // Por ferramenta: uma barra de cada uma por semana, e a soma bate
        let stacked = h.bars(year, byAgent: true, now: now, calendar: cal)
        XCTAssertEqual(stacked.count, 53 * AgentKind.allCases.count)
        XCTAssertEqual(stacked.reduce(0) { $0 + $1.tokens }, weekly.reduce(0) { $0 + $1.tokens })
        XCTAssertEqual(stacked.first { $0.start == date("2026-11-02", hour: 0) && $0.agent == .codex }?.tokens, 1160)

        // Tudo: desde junho de 2025, por mês
        let all = h.window(.all, now: now, calendar: cal)
        XCTAssertEqual(all, UsageWindow(start: date("2025-06-01", hour: 0), bucket: .month))
        let monthly = h.bars(all, byAgent: false, now: now, calendar: cal)
        XCTAssertEqual(monthly.count, 18)
        XCTAssertEqual(monthly.reduce(0) { $0 + $1.tokens }, 4 * 1160)
        XCTAssertEqual(h.totals(since: all.start, calendar: cal).replies, 4)
        XCTAssertEqual(h.totals(since: year.start, calendar: cal).replies, 3)
    }

    func testTopByClient() {
        var h = AgentUsageHistory()
        h.merge([rec("2026-11-10", client: .desktop), rec("2026-11-10", hour: 13, client: .desktop), rec("2026-11-10", agent: .codex, model: "gpt-5.5-codex")],
                coveredFrom: .distantPast, calendar: cal)
        let top = h.top(since: date("2026-11-01", hour: 0), by: { $0.client.title($0.agent) }, calendar: cal)
        XCTAssertEqual(top.map(\.name), ["Claude Desktop", "Codex CLI"])
    }
}

final class ClaudeCredentialsTests: XCTestCase {
    private let json = #"{"claudeAiOauth":{"accessToken":"tok","expiresAt":1800000000000,"subscriptionType":"max"}}"#

    func testParsesLogin() {
        let c = ClaudePlanLimits.parse(credentials: Data(json.utf8))
        XCTAssertEqual(c?.token, "tok")
        XCTAssertEqual(c?.plan, "Max")
        XCTAssertEqual(c?.expires, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNil(ClaudePlanLimits.parse(credentials: Data("{}".utf8)))
    }

    func testDecodesSecurityToolOutput() {
        // Texto com a quebra de linha do `security -w`
        XCTAssertEqual(ClaudePlanLimits.decode(securityOutput: Data((json + "\n").utf8)), Data(json.utf8))
        // Em hexadecimal, quando o conteúdo não é texto simples
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(ClaudePlanLimits.decode(securityOutput: Data((hex + "\n").utf8)), Data(json.utf8))
        XCTAssertNil(ClaudePlanLimits.decode(securityOutput: Data("\n".utf8)))
    }
}
