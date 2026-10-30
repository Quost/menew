import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Backup dos ajustes num arquivo `.menew` (property list): ajustes, atalhos, snippets, perfis e automações.
/// Notas e o histórico do clipboard só entram se você marcar; notas protegidas nunca saem das Chaves do macOS.
@MainActor
enum Backup {
    static let fileType = UTType(filenameExtension: "menew", conformingTo: .propertyList) ?? .propertyList

    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Menew", isDirectory: true)
    }

    private static let baseFiles = ["snippets.json", "profiles.json", "automations.json"]

    /// Coisas desta máquina ou do momento, que não fazem sentido em outro Mac
    private static func skipped(_ key: String) -> Bool {
        key.hasPrefix("NSWindow Frame") || key.hasPrefix("NSStatusItem") || key.hasPrefix("SU")
            || ["migratedFromMeuMenu", "paused", "pausedUntil", "softwareDim"].contains(key)
    }

    // MARK: Exportar

    static func export(notes: Bool, clipboard: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [fileType]
        let day = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Menew \(day).menew"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var files: [String: Data] = [:]
        for name in baseFiles { files[name] = try? Data(contentsOf: dir.appendingPathComponent(name)) }
        if notes, let data = try? Data(contentsOf: dir.appendingPathComponent("notes.json")),
           let list = try? JSONDecoder().decode([Note].self, from: data) {
            files["notes.json"] = try? JSONEncoder().encode(list.filter { !$0.secure })
        }
        if clipboard {
            files["history.json"] = try? Data(contentsOf: dir.appendingPathComponent("history.json"))
            let images = dir.appendingPathComponent("images", isDirectory: true)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: images.path)) ?? [] {
                files["images/" + name] = try? Data(contentsOf: images.appendingPathComponent(name))
            }
        }

        let all = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let plist: [String: Any] = [
            "format": 1,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "created": Date(),
            "defaults": all.filter { !skipped($0.key) },
            "files": files,
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try data.write(to: url, options: .atomic)
            HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Backup salvo"))
        } catch {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para salvar o backup"), duration: 2.5)
        }
    }

    // MARK: Importar

    static func pickAndImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [fileType]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["format"] as? Int == 1 else {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Este arquivo não é um backup do Menew"), duration: 2.5)
            return
        }
        let files = plist["files"] as? [String: Data] ?? [:]
        let alert = NSAlert()
        alert.messageText = L("Restaurar este backup?")
        alert.informativeText = L("Ajustes, atalhos, snippets, perfis e automações deste Mac serão trocados pelos do backup. Notas e clipboard só se estiverem nele, e as notas que já estão aqui são mantidas. O Menew vai reabrir.")
        alert.addButton(withTitle: L("Restaurar"))
        alert.addButton(withTitle: L("Cancelar"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let defaults = UserDefaults.standard
        for (key, value) in plist["defaults"] as? [String: Any] ?? [:] where !skipped(key) { defaults.set(value, forKey: key) }
        defaults.synchronize()

        let fm = FileManager.default
        try? fm.createDirectory(at: dir.appendingPathComponent("images", isDirectory: true), withIntermediateDirectories: true)
        for (name, data) in files {
            // Só nomes conhecidos ou imagens do clipboard; nada fora da pasta do Menew
            let allowed = baseFiles.contains(name) || name == "history.json" || name == "notes.json"
                || (name.hasPrefix("images/") && !name.dropFirst(7).contains("/") && !name.contains(".."))
            guard allowed else { continue }
            if name == "notes.json" { mergeNotes(data); continue }
            try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
        relaunch()
    }

    /// Notas do backup entram junto com as daqui; a mesma nota fica com a versão mais recente
    private static func mergeNotes(_ data: Data) {
        let url = dir.appendingPathComponent("notes.json")
        guard let incoming = try? JSONDecoder().decode([Note].self, from: data) else { return }
        var notes = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Note].self, from: $0) } ?? []
        for n in incoming where !n.secure {
            if let i = notes.firstIndex(where: { $0.id == n.id }) {
                if !notes[i].secure, n.updated > notes[i].updated { notes[i] = n }
            } else {
                notes.append(n)
            }
        }
        if let out = try? JSONEncoder().encode(notes) { try? out.write(to: url, options: .atomic) }
    }

    /// Abre de novo depois de fechar, para tudo ser lido do zero
    private static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}

/// Seção "Backup" nos Ajustes
struct BackupSection: View {
    @State private var notes = false
    @State private var clipboard = false

    var body: some View {
        GlassSection(title: L("Backup"),
                     footer: L("Um arquivo .menew com ajustes, atalhos, snippets, perfis e automações, para guardar ou levar para outro Mac. Notas protegidas nunca entram.")) {
            ToggleRow(title: L("Incluir notas"), isOn: $notes)
            RowDivider()
            ToggleRow(title: L("Incluir histórico do clipboard"), isOn: $clipboard)
            RowDivider()
            SettingRow(title: L("Ajustes e dados")) {
                HStack(spacing: 6) {
                    PillButton(title: L("Restaurar…"), icon: "square.and.arrow.down") { Backup.pickAndImport() }
                    PillButton(title: L("Exportar…"), icon: "square.and.arrow.up") { Backup.export(notes: notes, clipboard: clipboard) }
                }
            }
        }
    }
}
