import AppKit
import IOKit.pwr_mgt

/// Ações rápidas estilo "canivete suíço"
@MainActor
final class Toolbox: ObservableObject {
    @Published var keepAwake = false
    @Published var hiddenFiles = false
    @Published var desktopIconsHidden = false
    @Published var toast: String?
    let cleaning = CleaningController()

    private var assertionID: IOPMAssertionID = 0
    private var awakeUntil: Timer?

    init() {
        hiddenFiles = Self.finderBool("AppleShowAllFiles") ?? false
        desktopIconsHidden = (Self.finderBool("CreateDesktop") ?? true) == false
    }

    func show(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.toast == msg { self?.toast = nil }
        }
    }

    // MARK: Manter acordado (tipo Amphetamine/caffeinate)

    func setKeepAwake(_ on: Bool, minutes: Int? = nil) {
        awakeUntil?.invalidate()
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        keepAwake = false
        guard on else { return }
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "Menew: manter acordado" as CFString, &assertionID)
        keepAwake = r == kIOReturnSuccess
        if let minutes, keepAwake {
            awakeUntil = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.setKeepAwake(false) }
            }
        }
    }

    // MARK: Finder

    private static func finderBool(_ key: String) -> Bool? {
        let out = Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", key])
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if out.isEmpty { return nil }
        return ["1", "true", "yes"].contains(out)
    }

    func toggleHiddenFiles() {
        hiddenFiles.toggle()
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", hiddenFiles ? "true" : "false"])
        Shell.run("/usr/bin/killall", ["Finder"])
    }

    func toggleDesktopIcons() {
        desktopIconsHidden.toggle()
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", desktopIconsHidden ? "false" : "true"])
        Shell.run("/usr/bin/killall", ["Finder"])
    }

    func emptyTrash() {
        let alert = NSAlert()
        alert.messageText = "Esvaziar a Lixeira?"
        alert.informativeText = "Os itens serão apagados permanentemente."
        alert.addButton(withTitle: "Esvaziar")
        alert.addButton(withTitle: "Cancelar")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runAppleScript("tell application \"Finder\" to empty trash")
    }

    func ejectAll() {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var count = 0
        for v in vols {
            guard let r = try? v.resourceValues(forKeys: Set(keys)),
                  r.volumeIsEjectable == true || (r.volumeIsInternal == false && v.path != "/") else { continue }
            if (try? NSWorkspace.shared.unmountAndEjectDevice(at: v)) != nil { count += 1 }
        }
        show(count == 0 ? "Nenhum disco para ejetar" : "\(count) disco(s) ejetado(s)")
    }

    // MARK: Sistema

    func toggleDarkMode() {
        runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    }

    func lockScreen() {
        Shell.run("/usr/bin/pmset", ["displaysleepnow"])
    }

    func screenshotToClipboard() {
        // vai direto pro clipboard → aparece no histórico
        DispatchQueue.global().async { Shell.run("/usr/sbin/screencapture", ["-i", "-c"]) }
    }

    func pickColor(clipboard: ClipboardManager) {
        NSColorSampler().show { [weak self] color in
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                             Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
            MainActor.assumeIsolated {
                clipboard.copyText(hex)
                self?.show("Cor \(hex) copiada")
            }
        }
    }

    func plainTextClipboard() {
        let pb = NSPasteboard.general
        guard let s = pb.string(forType: .string) else { show("Clipboard não tem texto"); return }
        pb.clearContents()
        pb.setString(s, forType: .string)
        show("Formatação removida")
    }

    func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func runAppleScript(_ source: String) {
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if err != nil { show("Permita o Menew em Automação nos Ajustes") }
    }
}
