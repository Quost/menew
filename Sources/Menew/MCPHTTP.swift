import Foundation
import Network

/// O servidor MCP também pela rede, para agentes que rodam num contêiner (Docker) e não conseguem abrir o
/// `Menew --mcp` do Mac. Desligado por padrão. Só escuta no próprio Mac (127.0.0.1; o Docker Desktop entrega
/// `host.docker.internal` ali) e só responde a quem manda o token, no caminho (`/mcp/<token>`) ou no cabeçalho
/// `Authorization: Bearer`. Cada pedido vai para um `Menew --mcp` filho, o mesmo que os agentes do Mac usam.
final class MCPHTTP: @unchecked Sendable {
    static let shared = MCPHTTP()
    static let enabledKey = "mcp.http"
    static let defaultPort: UInt16 = 47833
    private static let tokenKey = "mcp.http.token"
    private static let maxBody = 1 << 20

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var port: UInt16 {
        let p = UserDefaults.standard.integer(forKey: "mcp.http.port")
        return (1024...65535).contains(p) ? UInt16(p) : defaultPort
    }

    /// Criado na primeira vez; trocar o token desliga quem tinha o antigo
    static var token: String {
        if let t = UserDefaults.standard.string(forKey: tokenKey), t.count >= 32 { return t }
        let t = newToken()
        UserDefaults.standard.set(t, forKey: tokenKey)
        return t
    }

    static func resetToken() { UserDefaults.standard.set(newToken(), forKey: tokenKey) }

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// O endereço que um contêiner usa para chegar ao Mac
    static var dockerURL: String { "http://host.docker.internal:\(port)/mcp/\(token)" }
    static var localURL: String { "http://127.0.0.1:\(port)/mcp/\(token)" }

    private let queue = DispatchQueue(label: "menew.mcp.http")
    private let child = MCPChild()
    private var listener: NWListener?
    private(set) var error: String?

    /// Liga ou desliga conforme a preferência (chamar ao abrir o app e quando ela muda)
    func sync() {
        let on = Self.isEnabled
        queue.async { [self] in
            if on, listener == nil { start() } else if !on, listener != nil { stop() }
        }
    }

    private func start() {
        _ = Self.token
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] s in
                if case .failed(let e) = s { self?.error = e.localizedDescription; self?.queue.async { self?.stop() } }
            }
            l.start(queue: queue)
            listener = l
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        child.stop()
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, Data())
    }

    private func receive(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { c.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            switch HTTPRequest.parse(buf, maxBody: Self.maxBody) {
            case .incomplete where !done && err == nil:
                self.receive(c, buf)
            case .complete(let req):
                let reply = self.respond(req)
                c.send(content: reply.data, completion: .contentProcessed { _ in c.cancel() })
            default:
                c.send(content: HTTPReply(status: 400, body: Data()).data, completion: .contentProcessed { _ in c.cancel() })
            }
        }
    }

    func respond(_ req: HTTPRequest) -> HTTPReply {
        let parts = req.path.split(separator: "?").first.map { $0.split(separator: "/").map(String.init) } ?? []
        guard parts.first == "mcp", parts.count <= 2 else { return HTTPReply(status: 404, body: Data()) }
        // Páginas da web abertas no Mac não podem falar com o Menew (proteção contra DNS rebinding)
        if let origin = req.headers["origin"], !Self.isLocalOrigin(origin) { return HTTPReply(status: 403, body: Data()) }
        let bearer = req.headers["authorization"].flatMap { $0.hasPrefix("Bearer ") ? String($0.dropFirst(7)) : nil }
        guard let given = parts.count == 2 ? parts[1] : bearer, Self.same(given, Self.token) else {
            return HTTPReply(status: 401, body: Data(), extra: ["WWW-Authenticate": "Bearer"])
        }
        switch req.method {
        case "POST": break
        case "GET", "DELETE": return HTTPReply(status: 405, body: Data(), extra: ["Allow": "POST"])
        default: return HTTPReply(status: 405, body: Data(), extra: ["Allow": "POST"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: req.body) else { return Self.rpcError(-32700, "Parse error") }
        let batch = json as? [[String: Any]]
        let messages = batch ?? (json as? [String: Any]).map { [$0] } ?? []
        guard !messages.isEmpty else { return Self.rpcError(-32600, "Invalid Request") }
        var replies: [Any] = []
        for m in messages {
            guard m["id"] != nil, m["method"] != nil else { child.notify(m); continue }
            replies.append(child.call(m) ?? ["jsonrpc": "2.0", "id": m["id"]!, "error": ["code": -32603, "message": "Menew could not answer"]])
        }
        guard !replies.isEmpty else { return HTTPReply(status: 202, body: Data()) }
        let out: Any = batch != nil ? replies : replies[0]
        let data = (try? JSONSerialization.data(withJSONObject: out, options: [.withoutEscapingSlashes])) ?? Data()
        return HTTPReply(status: 200, body: data, extra: ["Content-Type": "application/json"])
    }

    private static func rpcError(_ code: Int, _ message: String) -> HTTPReply {
        let obj: [String: Any] = ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": code, "message": message]]
        return HTTPReply(status: 400, body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data(), extra: ["Content-Type": "application/json"])
    }

    static func isLocalOrigin(_ origin: String) -> Bool {
        guard origin != "null", let host = URL(string: origin)?.host?.lowercased() else { return origin == "null" }
        return ["localhost", "127.0.0.1", "::1", "[::1]", "host.docker.internal"].contains(host)
    }

    /// Comparação em tempo constante
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// Um `Menew --mcp` que fica aberto e responde aos pedidos, um de cada vez
final class MCPChild: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()

    func call(_ msg: [String: Any]) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        for _ in 0..<2 {
            guard write(msg) else { restart(); continue }
            if let reply = readReply(id: msg["id"]) { return reply }
            restart()
        }
        return nil
    }

    func notify(_ msg: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        if !write(msg) { restart() }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        restart(relaunch: false)
    }

    private func write(_ msg: [String: Any]) -> Bool {
        if process?.isRunning != true { restart() }
        guard let input, let data = try? JSONSerialization.data(withJSONObject: msg, options: [.withoutEscapingSlashes]) else { return false }
        do { try input.write(contentsOf: data + Data("\n".utf8)); return true } catch { return false }
    }

    /// Lê linhas até a resposta com o mesmo id (o filho só responde a pedidos)
    private func readReply(id: Any?) -> [String: Any]? {
        guard let output else { return nil }
        let want = id.map { "\($0)" }
        while true {
            if let nl = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if obj["id"].map({ "\($0)" }) == want { return obj }
                continue
            }
            let chunk = output.availableData
            guard !chunk.isEmpty else { return nil }
            pending.append(chunk)
        }
    }

    private func restart(relaunch: Bool = true) {
        if let p = process, p.isRunning { p.terminate() }
        try? input?.close()
        process = nil; input = nil; output = nil; pending = Data()
        guard relaunch, let exe = Bundle.main.executableURL else { return }
        let p = Process()
        p.executableURL = exe
        p.arguments = [MCPServer.flag]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }
        process = p
        input = inPipe.fileHandleForWriting
        output = outPipe.fileHandleForReading
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    enum Parse { case incomplete, complete(HTTPRequest), invalid }

    static func parse(_ data: Data, maxBody: Int) -> Parse {
        let sep = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: sep) else { return data.count > 16384 ? .invalid : .incomplete }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return .invalid }
        var headers: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true { return .invalid }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxBody else { return .invalid }
        let bodyStart = end.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]
        return .complete(HTTPRequest(method: String(first[0]).uppercased(), path: String(first[1]), headers: headers, body: Data(body)))
    }
}

struct HTTPReply {
    let status: Int
    let body: Data
    var extra: [String: String] = [:]

    var data: Data {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { head += "\(k): \(v)\r\n" }
        return Data((head + "\r\n").utf8) + body
    }
}

/// Wrappers do Pi que rodam num contêiner e leem um `mcp.json` (como `~/.<nome>/mcp.json` com `agent/` ao lado e um
/// `system_info.json` de Linux). Ligar escreve a entrada `menew` apontando para o servidor pela rede.
struct MCPDockerClient: Identifiable, Hashable {
    let dir: URL
    var id: String { dir.path }
    var name: String { "Pi · ~/" + dir.lastPathComponent }
    var config: URL { dir.appendingPathComponent("mcp.json") }

    static func all() -> [MCPDockerClient] {
        PiLog.roots().map { $0.deletingLastPathComponent() }.filter(isContainer).map(MCPDockerClient.init)
    }

    static func isContainer(_ dir: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("mcp.json").path),
              let data = try? Data(contentsOf: dir.appendingPathComponent("system_info.json")),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (info["os"] as? String ?? "").lowercased().hasPrefix("linux")
    }

    var isInstalled: Bool {
        guard let data = try? Data(contentsOf: config), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (obj["mcpServers"] as? [String: Any])?["menew"] != nil
    }

    static var entry: [String: Any] { ["type": "http", "url": MCPHTTP.dockerURL] }

    /// Liga ou desliga; devolve a mensagem de erro, se houver
    func set(_ on: Bool) -> String? {
        let fm = FileManager.default
        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: config) {
            guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return L("O arquivo de configuração não é um JSON que o Menew consiga editar") }
            obj = o
            let backup = config.appendingPathExtension("menew-backup")
            if !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: config, to: backup) }
        }
        var servers = obj["mcpServers"] as? [String: Any] ?? [:]
        servers["menew"] = on ? Self.entry : nil
        obj["mcpServers"] = servers
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]),
              (try? data.write(to: config, options: .atomic)) != nil else { return L("Não consegui gravar o arquivo") }
        return nil
    }

    /// Para colar em qualquer agente num contêiner
    static var snippet: String {
        let obj: [String: Any] = ["mcpServers": ["menew": entry]]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
