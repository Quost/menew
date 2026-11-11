import AppKit
import Foundation

/// Hooks por plugin, para as ferramentas que não rodam um comando a cada evento (Pi, OpenCode e Amp só carregam
/// plugins em TypeScript/JavaScript). O Menew põe um plugin dele na pasta de plugins de cada uma; o plugin escreve cada
/// evento como uma linha num arquivo ao lado dele (`menew-events.jsonl`) e o Menew lê esse arquivo. Escrever num arquivo,
/// e não chamar o Menew, faz funcionar também quando a ferramenta roda num container com a pasta montada do Mac.
enum AgentPlugins {
    static let eventsName = "menew-events.jsonl"

    static func supports(_ a: AgentKind) -> Bool { [.pi, .opencode, .amp].contains(a) }

    /// Onde o plugin fica (o Pi pode ter mais de uma pasta: a dele e as dos agentes feitos a partir dele)
    static func targets(_ a: AgentKind) -> [URL] {
        let h = AgentFiles.home
        switch a {
        case .pi:
            var roots = PiLog.roots()
            let own = h.appendingPathComponent(".pi/agent")
            if FileManager.default.fileExists(atPath: own.path), !roots.contains(own) { roots.append(own) }
            return roots.map { $0.appendingPathComponent("extensions/menew.ts") }
        case .opencode: return [h.appendingPathComponent(".config/opencode/plugins/menew.js")]
        case .amp: return [h.appendingPathComponent(".config/amp/plugins/menew.ts")]
        default: return []
        }
    }

    static func status(_ a: AgentKind) -> AgentHooks.Status {
        let fm = FileManager.default
        let list = targets(a)
        let present = list.filter { fm.fileExists(atPath: $0.path) }
        if present.isEmpty { return .notInstalled }
        let current = present.allSatisfy { (try? String(contentsOf: $0, encoding: .utf8)) == source(a) }
        return current && present.count == list.count ? .installed : .outdated
    }

    static func apply(_ a: AgentKind, install: Bool) throws {
        let fm = FileManager.default
        for url in targets(a) {
            if install {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try source(a).write(to: url, atomically: true, encoding: .utf8)
            } else {
                try? fm.removeItem(at: url)
                try? fm.removeItem(at: url.deletingLastPathComponent().appendingPathComponent(eventsName))
            }
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { AgentEventFiles.shared.reload() } }
    }

    /// O arquivo de eventos de cada plugin instalado
    static func eventFiles() -> [(AgentKind, URL)] {
        [AgentKind.pi, .opencode, .amp].flatMap { a in
            targets(a).filter { FileManager.default.fileExists(atPath: $0.path) }
                .map { (a, $0.deletingLastPathComponent().appendingPathComponent(eventsName)) }
        }
    }

    // MARK: O código dos plugins

    /// Comum aos três: acha o arquivo ao lado do plugin e acrescenta uma linha por evento. Nunca lança erro.
    private static func prelude(_ agent: String) -> String {
        """
        // Menew (app da barra de menus do Mac): avisa quando o \(agent) começa, usa uma ferramenta e termina.
        // Só acrescenta uma linha em menew-events.jsonl, nesta pasta; nada sai do computador. Para tirar, desligue no Menew.
        import { appendFileSync } from "node:fs";
        import { dirname, join } from "node:path";
        import { fileURLToPath } from "node:url";

        let here = "";
        try { here = dirname(fileURLToPath(import.meta.url)); } catch { here = typeof __dirname === "string" ? __dirname : process.cwd(); }
        const file = join(here, "\(eventsName)");
        const fallback = `${process.pid}-${Date.now()}`;

        function send(event, session, extra = {}) {
          try {
            appendFileSync(file, JSON.stringify({ agent: "\(agent)", event, session: session || fallback, cwd: process.cwd(),
              pid: process.pid, platform: process.platform, time: Date.now(), ...extra }) + "\\n");
          } catch {}
        }

        function text(v) {
          if (typeof v === "string") return v;
          if (Array.isArray(v)) return v.map(text).filter(Boolean).join("\\n");
          if (v && typeof v === "object") return text(v.text ?? v.content ?? v.parts);
          return undefined;
        }

        """
    }

    static func source(_ a: AgentKind) -> String {
        switch a {
        case .pi:
            return prelude("pi") + """
            export default function (pi) {
              pi.on("session_start", () => send("SessionStart"));
              pi.on("input", (e) => { send("UserPromptSubmit", undefined, { prompt: text(e?.text ?? e?.input ?? e?.prompt ?? e) }); });
              pi.on("tool_execution_start", (e) => send("PreToolUse", undefined, { tool_name: e?.toolName ?? e?.name ?? e?.tool, tool_input: e?.args ?? e?.input ?? {} }));
              pi.on("agent_settled", () => send("Stop"));
              pi.on("session_shutdown", () => send("SessionEnd"));
            }

            """
        case .opencode:
            return prelude("opencode") + """
            export const MenewPlugin = async ({ directory }) => ({
              "chat.message": async (input, output) => {
                send("UserPromptSubmit", input?.sessionID, { cwd: directory, prompt: text(output?.parts ?? output?.message) });
              },
              "tool.execute.before": async (input, output) => {
                send("PreToolUse", input?.sessionID, { cwd: directory, tool_name: input?.tool, tool_input: output?.args ?? {} });
              },
              event: async ({ event }) => {
                const sid = event?.properties?.sessionID ?? event?.properties?.info?.sessionID;
                if (event?.type === "session.idle") send("Stop", sid, { cwd: directory });
                else if (event?.type === "permission.updated" || event?.type === "permission.asked") send("Notification", sid, { cwd: directory, message: "Needs your permission" });
                else if (event?.type === "session.deleted") send("SessionEnd", sid, { cwd: directory });
              },
            });

            """
        case .amp:
            return prelude("amp") + """
            export default function (amp) {
              amp.on("agent.start", (e) => { send("UserPromptSubmit", e?.thread?.id, { prompt: text(e?.message) }); });
              amp.on("tool.result", (e) => { send("PostToolUse", e?.thread?.id, { tool_name: e?.tool, tool_input: e?.input ?? {} }); });
              amp.on("agent.end", (e) => { send("Stop", e?.thread?.id); });
            }

            """
        default:
            return ""
        }
    }
}

/// Lê o que os plugins escrevem e passa para a central de agentes, como se fosse um hook
@MainActor
final class AgentEventFiles {
    static let shared = AgentEventFiles()
    private var offsets: [String: UInt64] = [:]
    private var files: [(AgentKind, URL)] = []
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { AgentEventFiles.shared.poll() }
        }
        timer?.tolerance = 0.5
    }

    /// Começa do fim de cada arquivo: o que foi escrito antes de o Menew abrir já passou
    func reload() {
        files = AgentPlugins.eventFiles()
        for (_, url) in files where offsets[url.path] == nil {
            offsets[url.path] = Self.size(url)
        }
    }

    private static func size(_ url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    func poll() {
        for (agent, url) in files {
            let size = Self.size(url)
            var offset = offsets[url.path] ?? 0
            if size < offset { offset = 0 }   // o arquivo foi zerado
            guard size > offset, let h = try? FileHandle(forReadingFrom: url) else { offsets[url.path] = offset; continue }
            try? h.seek(toOffset: offset)
            let data = (try? h.readToEnd()) ?? Data()
            try? h.close()
            // Só linhas inteiras; a última, se ainda está sendo escrita, fica para a próxima vez
            guard let lastNL = data.lastIndex(of: 0x0A) else { offsets[url.path] = offset; continue }
            offsets[url.path] = offset + UInt64(lastNL - data.startIndex + 1)
            for line in data[..<lastNL].split(separator: 0x0A) {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                AgentHub.shared.handle(Self.info(obj, agent: agent))
            }
            // Não deixa o arquivo crescer para sempre
            if size > 512 * 1024, (try? Data().write(to: url)) != nil { offsets[url.path] = 0 }
        }
    }

    /// O mesmo recado que o comando de hook monta
    static func info(_ obj: [String: Any], agent: AgentKind) -> [String: String] {
        var info: [String: String] = ["agent": agent.rawValue]
        info["event"] = obj["event"] as? String
        info["session"] = obj["session"].map { "\($0)" }
        info["cwd"] = obj["cwd"] as? String
        info["message"] = (obj["message"] as? String).map { String($0.prefix(200)) }
        if let (tool, detail) = AgentHookCommand.step(obj) {
            info["tool"] = tool
            info["detail"] = detail
        }
        info["prompt"] = (obj["prompt"] as? String).flatMap(AgentStep.task)
        // O processo só é deste Mac quando o plugin roda no macOS (num container Linux, o número não vale aqui)
        if obj["platform"] as? String == "darwin", let pid = (obj["pid"] as? NSNumber)?.int32Value, ProcessTree.isAlive(pid) {
            info["pid"] = String(pid)
            if let app = ProcessTree.ancestors(of: pid).lazy.compactMap({ NSRunningApplication(processIdentifier: $0) })
                .first(where: { $0.activationPolicy == .regular }) {
                info["app"] = app.bundleIdentifier
                info["appPID"] = String(app.processIdentifier)
            }
        }
        return info
    }
}
