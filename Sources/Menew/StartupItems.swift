import AppKit
import SwiftUI

/// O que abre com o Mac e roda em segundo plano: agentes e serviços (LaunchAgents/LaunchDaemons) de cada app,
/// com o app dono, se está ligado e onde fica o arquivo. Só lê; para desligar, abre os Ajustes do Sistema.
@MainActor
enum StartupItems {
    struct Item: Identifiable, Hashable {
        var id: String { url.path }
        let label: String
        let url: URL
        let program: String
        let scope: Scope
        let disabled: Bool
        let atLoad: Bool
        /// Nome do app pelo caminho do programa (/Applications/Zoom.app/… → Zoom)
        var owner: String? {
            guard let r = program.range(of: #"[^/]+\.app"#, options: .regularExpression) else { return nil }
            return String(program[r].dropLast(4))
        }
    }

    enum Scope: Int, CaseIterable { case user, agents, daemons
        var title: String {
            switch self {
            case .user: L("Seus agentes")
            case .agents: L("Agentes de todos os usuários")
            case .daemons: L("Serviços do sistema")
            }
        }
        var folder: URL {
            switch self {
            case .user: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
            case .agents: URL(fileURLWithPath: "/Library/LaunchAgents")
            case .daemons: URL(fileURLWithPath: "/Library/LaunchDaemons")
            }
        }
    }

    nonisolated static func scan() -> [Item] {
        var out: [Item] = []
        for scope in Scope.allCases {
            let files = (try? FileManager.default.contentsOfDirectory(at: scope.folder, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.pathExtension == "plist" {
                guard let d = NSDictionary(contentsOf: url) as? [String: Any] else { continue }
                let label = d["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = d["Program"] as? String ?? (d["ProgramArguments"] as? [String])?.first ?? ""
                out.append(Item(label: label, url: url, program: program, scope: scope,
                                disabled: d["Disabled"] as? Bool ?? false, atLoad: d["RunAtLoad"] as? Bool ?? false || d["KeepAlive"] != nil))
            }
        }
        return out.sorted { ($0.scope.rawValue, $0.label) < ($1.scope.rawValue, $1.label) }
    }

    private static var window: NSWindow?

    /// Para as capturas de tela
    static let demo: [Item] = [
        Item(label: "com.spotify.webhelper", url: URL(fileURLWithPath: "/tmp/a.plist"), program: "/Applications/Spotify.app/Contents/MacOS/SpotifyWebHelper",
             scope: .user, disabled: false, atLoad: true),
        Item(label: "com.google.keystone.agent", url: URL(fileURLWithPath: "/tmp/b.plist"), program: "/Users/me/Library/Google/GoogleSoftwareUpdate/Agent",
             scope: .user, disabled: true, atLoad: false),
        Item(label: "us.zoom.updater", url: URL(fileURLWithPath: "/tmp/c.plist"), program: "/Applications/zoom.us.app/Contents/Frameworks/updater",
             scope: .agents, disabled: false, atLoad: true),
        Item(label: "com.docker.vmnetd", url: URL(fileURLWithPath: "/tmp/d.plist"), program: "/Library/PrivilegedHelperTools/com.docker.vmnetd",
             scope: .daemons, disabled: false, atLoad: true),
    ]

    static func show() {
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        let w = window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = L("Itens de login e em segundo plano")
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: StartupItemsView())
            w.center()
            return w
        }()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    static func openLoginItemsSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }
}

struct StartupItemsView: View {
    var demo: [StartupItems.Item]? = nil
    @State private var items: [StartupItems.Item] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Itens de login e em segundo plano")).font(.system(size: 17, weight: .bold))
            Text(L("Agentes e serviços que os apps instalaram para abrir com o Mac ou rodar escondidos. Para desligar um, use os Ajustes do Sistema."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if loading { ProgressView().controlSize(.small) }
                    ForEach(StartupItems.Scope.allCases, id: \.self) { scope in
                        let list = items.filter { $0.scope == scope }
                        if !list.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(scope.title) · \(list.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                VStack(spacing: 0) {
                                    ForEach(Array(list.enumerated()), id: \.element) { i, item in
                                        if i > 0 { RowDivider() }
                                        row(item)
                                    }
                                }
                                .glass()
                            }
                        }
                    }
                    if !loading && items.isEmpty {
                        Text(L("Nenhum agente instalado. 🎉")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                PillButton(title: L("Abrir Ajustes de itens de login"), icon: "gearshape", primary: true) { StartupItems.openLoginItemsSettings() }
            }
        }
        .padding(20).padding(.top, 18)
        .frame(minWidth: 480, minHeight: 400)
        .background(Theme.windowFill)
        .task {
            if let demo { items = demo; loading = false; return }
            items = await Task.detached { StartupItems.scan() }.value
            loading = false
        }
    }

    private func row(_ item: StartupItems.Item) -> some View {
        HStack(spacing: 10) {
            Group {
                if let owner = item.owner, let path = item.program.range(of: owner + ".app").map({ String(item.program[..<$0.upperBound]) }),
                   FileManager.default.fileExists(atPath: path) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
                } else {
                    Image(systemName: "gearshape.2").foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.owner ?? item.label).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                // Sem app dono, o nome já é o rótulo: embaixo vai o programa que ele roda
                Text(item.owner == nil ? item.program : item.label).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if item.disabled {
                Text(L("desligado")).font(.system(size: 10.5)).foregroundStyle(.secondary)
            } else if item.atLoad {
                Text(L("abre com o Mac")).font(.system(size: 10.5)).foregroundStyle(.orange)
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Mostrar no Finder"))
                .accessibilityLabel(L("Mostrar no Finder"))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }
}
