import AppKit
import IOKit.pwr_mgt

/// Ações rápidas estilo "canivete suíço"
@MainActor
final class Toolbox: ObservableObject {
    @Published var keepAwake = false
    /// Quando o "manter acordado" desliga sozinho (nil = até desligar)
    @Published var awakeUntil: Date?
    @Published var darkMode = Toolbox.systemIsDark
    @Published var ejectableCount = 0
    @Published var hiddenFiles = false
    @Published var desktopIconsHidden = false
    @Published var toast: String?
    let cleaning = CleaningController()

    private var assertionID: IOPMAssertionID = 0
    private var awakeTimer: Timer?

    init() {
        hiddenFiles = Self.finderBool("AppleShowAllFiles") ?? false
        desktopIconsHidden = (Self.finderBool("CreateDesktop") ?? true) == false
        // Acompanha o modo escuro mesmo quando ele muda fora do Menew
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.darkMode = Self.systemIsDark }
        }
    }

    /// Aparência do macOS (não a do Menew, que pode estar forçada nos Ajustes)
    static var systemIsDark: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return (CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String) == "Dark"
    }

    func show(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.toast == msg { self?.toast = nil }
        }
    }

    // MARK: Manter acordado (tipo Amphetamine/caffeinate)

    func setKeepAwake(_ on: Bool, minutes: Int? = nil) {
        awakeTimer?.invalidate()
        awakeUntil = nil
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
            awakeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
            awakeTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
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
        Shell.run("/usr/bin/killall", [L("Finder")])
    }

    func toggleDesktopIcons() {
        desktopIconsHidden.toggle()
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", desktopIconsHidden ? "false" : "true"])
        Shell.run("/usr/bin/killall", [L("Finder")])
    }

    func emptyTrash() {
        let alert = NSAlert()
        alert.messageText = L("Esvaziar a Lixeira?")
        alert.informativeText = L("Os itens serão apagados permanentemente.")
        alert.addButton(withTitle: L("Esvaziar"))
        alert.addButton(withTitle: L("Cancelar"))
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runAppleScript("tell application \"Finder\" to empty trash")
    }

    private static func ejectableVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return vols.filter { v in
            guard let r = try? v.resourceValues(forKeys: Set(keys)) else { return false }
            return r.volumeIsEjectable == true || (r.volumeIsInternal == false && v.path != "/")
        }
    }

    /// Atualiza os estados que podem mudar fora do Menew (ao abrir a aba)
    func refresh() {
        darkMode = Self.systemIsDark
        ejectableCount = Self.ejectableVolumes().count
    }

    func ejectAll() {
        var count = 0
        for v in Self.ejectableVolumes() where (try? NSWorkspace.shared.unmountAndEjectDevice(at: v)) != nil { count += 1 }
        ejectableCount = Self.ejectableVolumes().count
        show(count == 0 ? L("Nenhum disco para ejetar") : L("%d disco(s) ejetado(s)", count))
    }

    // MARK: Sistema

    func toggleDarkMode() {
        let target = !darkMode
        runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to \(target)")
        darkMode = Self.systemIsDark
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
                self?.show(L("Cor %@ copiada", hex))
            }
        }
    }

    func plainTextClipboard() {
        let pb = NSPasteboard.general
        guard let s = pb.string(forType: .string) else { show(L("Clipboard não tem texto")); return }
        pb.clearContents()
        pb.setString(s, forType: .string)
        show(L("Formatação removida"))
    }

    func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func runAppleScript(_ source: String) {
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if err != nil { show(L("Permita o Menew em Automação nos Ajustes")) }
    }
}
