import XCTest
@testable import Menew

final class MCPHTTPTests: XCTestCase {
    func testParsesRequestAndWaitsForBody() {
        let head = "POST /mcp/abc HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nAuthorization: Bearer t\r\n\r\n"
        guard case .incomplete = HTTPRequest.parse(Data((head + "ab").utf8), maxBody: 100) else { return XCTFail() }
        guard case .complete(let r) = HTTPRequest.parse(Data((head + "abcd").utf8), maxBody: 100) else { return XCTFail() }
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/mcp/abc")
        XCTAssertEqual(r.headers["authorization"], "Bearer t")
        XCTAssertEqual(String(decoding: r.body, as: UTF8.self), "abcd")
    }

    func testRejectsHugeBodyAndChunked() {
        guard case .invalid = HTTPRequest.parse(Data("POST / HTTP/1.1\r\nContent-Length: 999\r\n\r\n".utf8), maxBody: 10) else { return XCTFail() }
        guard case .invalid = HTTPRequest.parse(Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8), maxBody: 10) else { return XCTFail() }
    }

    func testAuthAndOrigin() {
        let s = MCPHTTP.shared
        let body = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        func req(_ path: String, _ h: [String: String] = [:]) -> HTTPRequest { HTTPRequest(method: "POST", path: path, headers: h, body: body) }
        XCTAssertEqual(s.respond(req("/mcp")).status, 401)
        XCTAssertEqual(s.respond(req("/mcp/wrong")).status, 401)
        XCTAssertEqual(s.respond(req("/other")).status, 404)
        XCTAssertEqual(s.respond(req("/mcp/\(MCPHTTP.token)", ["origin": "https://evil.example"])).status, 403)
        XCTAssertEqual(s.respond(req("/mcp/\(MCPHTTP.token)")).status, 202)
        XCTAssertEqual(s.respond(req("/mcp", ["authorization": "Bearer \(MCPHTTP.token)"])).status, 202)
        XCTAssertEqual(s.respond(HTTPRequest(method: "GET", path: "/mcp/\(MCPHTTP.token)", headers: [:], body: Data())).status, 405)
    }

    func testLocalOriginsAndCompare() {
        XCTAssertTrue(MCPHTTP.isLocalOrigin("http://localhost:3000"))
        XCTAssertTrue(MCPHTTP.isLocalOrigin("null"))
        XCTAssertFalse(MCPHTTP.isLocalOrigin("http://attacker.com"))
        XCTAssertTrue(MCPHTTP.same("abc", "abc"))
        XCTAssertFalse(MCPHTTP.same("abc", "abd"))
        XCTAssertFalse(MCPHTTP.same("abc", "abcd"))
    }

    func testDockerClientDetectionAndConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("menew-docker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"mcpServers":{"other":{"type":"http","url":"https://x"}}}"#.write(to: dir.appendingPathComponent("mcp.json"), atomically: true, encoding: .utf8)
        XCTAssertFalse(MCPDockerClient.isContainer(dir))
        try #"{"os":"linux 7.0-linuxkit"}"#.write(to: dir.appendingPathComponent("system_info.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(MCPDockerClient.isContainer(dir))
        let c = MCPDockerClient(dir: dir)
        XCTAssertNil(c.set(true))
        XCTAssertTrue(c.isInstalled)
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: c.config)) as! [String: Any]
        let servers = obj["mcpServers"] as! [String: Any]
        XCTAssertNotNil(servers["other"])
        XCTAssertEqual((servers["menew"] as? [String: Any])?["url"] as? String, MCPHTTP.dockerURL)
        XCTAssertNil(c.set(false))
        XCTAssertFalse(c.isInstalled)
    }
}
