import AppKit
import SwiftUI

/// Scripts como comandos da paleta, no formato dos Script Commands do Raycast: cada arquivo da pasta de scripts
/// vira um comando. O cabeçalho pode dar título, ícone e modo (`# @raycast.title`, `# @raycast.icon`, `# @raycast.mode`)
/// e um argumento (`# @raycast.argument1 { "placeholder": "…" }`), que é o texto digitado depois do título.
/// O Menew só roda um script quando você escolhe ele na paleta.
@MainActor
enum ScriptCommands {
    struct Script: Equatable {
        let url: URL
        let title: String
        let icon: String?
        let mode: Mode
        let argument: String?
        let packageName: String?
    }

    enum Mode: String { case silent, compact, fullOutput, inline }

    static var folder: URL {
        AppData.dir.appendingPathComponent("Scripts", isDirectory: true)
    }

    private static var cache: (date: Date, list: [Script]) = (.distantPast, [])

    /// Lê a pasta no máximo a cada 3 s (a paleta pede a cada tecla)
    static func scripts() -> [Script] {
        if Date().timeIntervalSince(cache.date) < 3 { return cache.list }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let list = files.filter { !$0.hasDirectoryPath && $0.pathExtension != "md" }.compactMap(parse).sorted { $0.title < $1.title }
        cache = (Date(), list)
        return list
    }

    /// Cabeçalho no estilo Raycast (também aceita `@menew.` no lugar de `@raycast.`)
    nonisolated static func parse(_ url: URL) -> Script? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let text = String(data: data.prefix(4096), encoding: .utf8) else { return nil }
        var meta: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
            guard let r = line.range(of: #"@(raycast|menew)\.(\w+)\s+(.*)$"#, options: .regularExpression) else { continue }
            let rest = line[r].drop(while: { $0 != "." }).dropFirst()
            let key = rest.prefix(while: { !$0.isWhitespace })
            meta[String(key)] = rest.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        }
        let title = meta["title"].flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        var argument: String?
        if let raw = meta["argument1"] {
            let json = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
            argument = (json?["placeholder"] as? String) ?? L("texto")
        }
        return Script(url: url, title: title, icon: meta["icon"], mode: Mode(rawValue: meta["mode"] ?? "") ?? .compact,
                      argument: argument, packageName: meta["packageName"])
    }

    static func paletteItems(raw: String) -> [PaletteItem] {
        let typed = raw.trimmingCharacters(in: .whitespaces)
        var items = scripts().map { s -> PaletteItem in
            // "traduzir olá mundo": o que vem depois do título é o argumento
            var arg: String?
            if s.argument != nil, typed.count > s.title.count,
               PaletteSearch.fold(String(typed.prefix(s.title.count))) == PaletteSearch.fold(s.title) {
                arg = String(typed.dropFirst(s.title.count)).trimmingCharacters(in: .whitespaces)
            }
            let icon: PaletteItem.Icon = s.icon.map { $0.count <= 2 ? .glyph($0) : .symbol("terminal", .gray) } ?? .symbol("terminal.fill", .gray)
            let subtitle = arg.map { L("Rodar com “%@”", $0) } ?? s.argument.map { L("Script · digite depois do nome: %@", $0) }
                ?? (s.packageName.map { L("Script · %@", $0) } ?? L("Script"))
            return PaletteItem(id: "script:\(s.url.lastPathComponent)", kind: .action, title: s.title, subtitle: subtitle,
                               keywords: "script \(s.url.lastPathComponent) \(arg.map { s.title + " " + $0 } ?? "")",
                               icon: icon) { run(s, argument: arg) }
        }
        items.append(PaletteItem(id: "action.scriptsfolder", kind: .action, title: L("Abrir pasta de scripts"),
                                 subtitle: L("Cada arquivo vira um comando da paleta"),
                                 keywords: "scripts script pasta folder raycast comandos commands shell bash python", icon: .symbol("folder.badge.gearshape", .gray)) {
            openFolder()
        })
        return items
    }

    static func openFolder() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            // Um exemplo e um guia curto para começar
            let example = folder.appendingPathComponent("hello.sh")
            try? """
            #!/bin/zsh
            # @raycast.title Hello from Menew
            # @raycast.icon 👋
            # @raycast.mode compact
            #
            # Each file in this folder becomes a command in Menew's palette (⌃⌥Space).
            # Modes: silent (nothing shown), compact (last line in a toast), fullOutput (a window with everything).
            # Add "# @raycast.argument1 { \\"placeholder\\": \\"name\\" }" and type the text after the title.

            echo "Hello! Today is $(date +%A)."
            """.write(to: example, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: example.path)
        }
        NSWorkspace.shared.open(folder)
    }

    /// Como rodar cada tipo de arquivo: executável roda direto; os outros pelo interpretador da extensão
    nonisolated static func launch(for url: URL) -> (String, [String]) {
        if FileManager.default.isExecutableFile(atPath: url.path) { return (url.path, []) }
        switch url.pathExtension.lowercased() {
        case "py": return ("/usr/bin/env", ["python3", url.path])
        case "js", "mjs": return ("/usr/bin/env", ["node", url.path])
        case "rb": return ("/usr/bin/env", ["ruby", url.path])
        case "applescript", "scpt": return ("/usr/bin/osascript", [url.path])
        case "swift": return ("/usr/bin/env", ["swift", url.path])
        default: return ("/bin/zsh", [url.path])
        }
    }

    struct Result { let status: Int32; let output: String; let error: String }

    /// Roda fora da tela principal, com até 2 minutos; a pasta de scripts é a pasta de trabalho
    nonisolated static func execute(_ s: Script, argument: String?) -> Result {
        let (exe, args) = launch(for: s.url)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args + (argument.map { [$0] } ?? [])
        p.currentDirectoryURL = s.url.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        // Apps abertos pelo Finder não herdam o PATH do terminal: inclui o Homebrew
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return Result(status: -1, output: "", error: error.localizedDescription) }
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timer)
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        timer.cancel()
        return Result(status: p.terminationStatus, output: String(decoding: o, as: UTF8.self), error: String(decoding: e, as: UTF8.self))
    }

    static func run(_ s: Script, argument: String?) {
        if s.argument != nil, (argument ?? "").isEmpty {
            HUD.show(icon: "character.cursor.ibeam", color: .orange, text: L("Digite o texto depois do nome do script"), duration: 2)
            return
        }
        if s.mode != .silent { HUD.show(icon: "terminal.fill", color: .gray, text: L("Rodando %@…", s.title), duration: nil) }
        Task {
            let r = await Task.detached(priority: .userInitiated) { execute(s, argument: argument) }.value
            let last = r.output.split(whereSeparator: \.isNewline).last.map(String.init)
            guard r.status == 0 else {
                let why = r.error.split(whereSeparator: \.isNewline).last.map(String.init) ?? last ?? L("código %d", Int(r.status))
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: "\(s.title): \(why)", duration: 3)
                return
            }
            switch s.mode {
            case .silent: HUD.hide()
            case .compact, .inline:
                HUD.show(icon: "checkmark.circle.fill", color: .green, text: last ?? L("%@ concluído", s.title), duration: 2.5)
            case .fullOutput:
                HUD.hide()
                showOutput(title: s.title, text: r.output)
            }
        }
    }

    private static func showOutput(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 460, height: 260)
        if let tv = scroll.documentView as? NSTextView {
            tv.string = text
            tv.isEditable = false
            tv.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Copiar"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
