import AppKit
import SwiftUI

/// Desinstalador, como o AppCleaner: escolha um app e o Menew acha o que ele deixou na Biblioteca
/// (preferências, caches, dados, containers, estado salvo, logs). Você revisa e tudo vai para a Lixeira, nada é apagado direto.
@MainActor
final class Uninstaller: ObservableObject {
    struct Leftover: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let size: Int64
        var selected = true
    }

    @Published var app: URL?
    @Published var appName = ""
    @Published var appIcon: NSImage?
    @Published var appSize: Int64 = 0
    @Published var leftovers: [Leftover] = []
    @Published var scanning = false
    @Published var problem: String?

    private static var window: NSWindow?
    private static let shared = Uninstaller()

    /// Para as capturas de tela: um app inventado com sobras
    static func demo() -> Uninstaller {
        let m = Uninstaller()
        m.app = URL(fileURLWithPath: "/Applications/Video Editor.app")
        m.appName = "Video Editor"
        m.appIcon = NSWorkspace.shared.icon(for: .applicationBundle)
        m.appSize = 1_240_000_000
        let lib = "/Users/me/Library/"
        m.leftovers = [("Application Support/Video Editor", 2_310_000_000), ("Caches/com.example.videoeditor", 845_000_000),
                       ("Containers/com.example.videoeditor", 120_000_000), ("Preferences/com.example.videoeditor.plist", 12_000),
                       ("Saved Application State/com.example.videoeditor.savedState", 48_000)]
            .map { Leftover(url: URL(fileURLWithPath: lib + $0.0), size: $0.1) }
        return m
    }

    static func show(app: URL? = nil) {
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        let w = window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = L("Desinstalar app")
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: UninstallerView(model: shared))
            w.center()
            return w
        }()
        window = w
        if let app { shared.choose(app) }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func pick() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = L("Escolher")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        choose(url)
    }

    func choose(_ url: URL) {
        problem = nil
        leftovers = []
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            app = nil
            problem = L("Isso não parece ser um app.")
            return
        }
        if let reason = Self.refusal(url: url, id: id) {
            app = nil
            problem = reason
            return
        }
        app = url
        appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
        scanning = true
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? appName
        Task {
            let (size, found) = await Task.detached(priority: .userInitiated) {
                (Self.size(of: url), Self.leftovers(id: id, name: name, home: FileManager.default.homeDirectoryForCurrentUser))
            }.value
            guard app == url else { return }
            appSize = size
            leftovers = found
            scanning = false
        }
    }

    /// Apps do sistema, o próprio Menew e apps fora de uma pasta de aplicativos ficam de fora
    nonisolated static func refusal(url: URL, id: String) -> String? {
        if id.hasPrefix("com.apple.") || url.path.hasPrefix("/System/") { return L("Apps do macOS não podem ser desinstalados.") }
        if id == Bundle.main.bundleIdentifier { return L("Para tirar o Menew, use Sair do Menew e arraste-o para a Lixeira.") }
        return nil
    }

    /// Onde os apps costumam deixar coisas, pelo identificador (com.empresa.app) ou pelo nome
    nonisolated static func leftovers(id: String, name: String, home: URL) -> [Leftover] {
        let lib = home.appendingPathComponent("Library")
        let fm = FileManager.default
        var urls: [URL] = []
        let exact = [
            "Application Support/\(id)", "Application Support/\(name)", "Caches/\(id)", "Caches/\(name)",
            "Preferences/\(id).plist", "Containers/\(id)", "Saved Application State/\(id).savedState",
            "Logs/\(id)", "Logs/\(name)", "HTTPStorages/\(id)", "HTTPStorages/\(id).binarycookies", "WebKit/\(id)",
            "Cookies/\(id).binarycookies", "Application Scripts/\(id)", "Caches/SentryCrash/\(name)",
        ]
        for path in exact {
            let u = lib.appendingPathComponent(path)
            if fm.fileExists(atPath: u.path) { urls.append(u) }
        }
        // Grupos e agentes que levam o identificador no nome (TEAMID.com.empresa.app, com.empresa.app.helper.plist)
        for dir in ["Group Containers", "LaunchAgents", "Preferences"] {
            let base = lib.appendingPathComponent(dir)
            for item in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] where item.contains(id) {
                let u = base.appendingPathComponent(item)
                if !urls.contains(u) { urls.append(u) }
            }
        }
        // Nomes curtos ("Notes", "Mail") pegariam pastas de outros apps: só pelo nome se ele for bem específico
        if name.count < 4 { urls.removeAll { $0.lastPathComponent == name } }
        return urls.map { Leftover(url: $0, size: size(of: $0)) }.sorted { $0.size > $1.size }
    }

    nonisolated static func size(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        guard isDir.boolValue else { return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [], errorHandler: { _, _ in true })
        while let f = e?.nextObject() as? URL {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    var total: Int64 { appSize + leftovers.filter(\.selected).reduce(0) { $0 + $1.size } }

    /// Fecha o app se estiver aberto e manda tudo para a Lixeira
    func uninstall() {
        guard let app else { return }
        let id = Bundle(url: app)?.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == id }
        running.forEach { $0.terminate() }
        Task {
            if !running.isEmpty { try? await Task.sleep(for: .seconds(1.5)) }
            var failed = 0
            for url in [app] + leftovers.filter(\.selected).map(\.url) {
                do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { failed += 1 }
            }
            let freed = Fmt.bytes(total)
            if failed == 0 {
                HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("%@ foi para a Lixeira (%@)", appName, freed), duration: 2)
                self.app = nil
                leftovers = []
            } else {
                problem = L("%d item(ns) não puderam ir para a Lixeira. Talvez precise da sua senha: arraste-os pelo Finder.", failed)
            }
        }
    }
}

struct UninstallerView: View {
    @ObservedObject var model: Uninstaller
    @State private var dropping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let app = model.app {
                HStack(spacing: 12) {
                    if let icon = model.appIcon { Image(nsImage: icon).resizable().frame(width: 48, height: 48) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.appName).font(.system(size: 17, weight: .bold))
                        Text(app.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button(L("Outro app…")) { model.pick() }
                }
                Text(L("O que vai para a Lixeira")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 0) {
                        row(icon: "app.dashed", title: model.appName + ".app", size: model.appSize, selected: .constant(true), fixed: true)
                        ForEach($model.leftovers) { $l in
                            RowDivider()
                            row(icon: "folder", title: l.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), size: l.size, selected: $l.selected)
                        }
                        if model.scanning {
                            RowDivider()
                            HStack { ProgressView().controlSize(.small); Text(L("Procurando sobras…")).font(.system(size: 12)) }.padding(10)
                        } else if model.leftovers.isEmpty {
                            RowDivider()
                            Text(L("Nenhuma sobra encontrada na Biblioteca.")).font(.system(size: 12)).foregroundStyle(.secondary).padding(10)
                        }
                    }
                    .glass()
                }
                HStack {
                    Text(L("Total: %@", Fmt.bytes(model.total))).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Spacer()
                    PillButton(title: L("Mover para a Lixeira"), icon: "trash", primary: true) { model.uninstall() }
                        .disabled(model.scanning)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "trash.square").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text(L("Arraste um app para cá")).font(.system(size: 15, weight: .semibold))
                    Text(L("O Menew acha as preferências, caches e dados que ele deixou e manda tudo para a Lixeira."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
                    PillButton(title: L("Escolher app…"), icon: "folder") { model.pick() }
                }
                .frame(maxWidth: .infinity)
                .padding(30)
                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(dropping ? Color.accentColor : Color.secondary.opacity(0.3),
                                                                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                Spacer()
            }
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.orange)
            }
        }
        .padding(20).padding(.top, 18)
        .frame(minWidth: 460, minHeight: 420)
        .background(Theme.windowFill)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { model.choose(url) } }
            }
            return true
        }
    }

    private func row(icon: String, title: String, size: Int64, selected: Binding<Bool>, fixed: Bool = false) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: selected).labelsHidden().disabled(fixed)
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            Text(title).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(Fmt.bytes(size)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }
}
