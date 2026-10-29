import AppKit
import SwiftUI

// MARK: Modelo

/// Um app do perfil e onde ficavam as janelas dele (coordenadas da Acessibilidade, da frente para trás)
struct ProfileApp: Codable, Equatable, Identifiable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var path: String
    var frames: [CGRect]
}

/// Perfil de trabalho: abre os apps, põe cada janela no lugar e ajusta o Mac de uma vez
struct WorkProfile: Codable, Equatable, Identifiable {
    enum Mic: String, Codable, CaseIterable { case keep, mute, unmute }
    enum Look: String, Codable, CaseIterable { case keep, light, dark }

    var id = UUID()
    var name: String
    var icon = "briefcase.fill"
    var apps: [ProfileApp] = []
    var keepAwake = false
    var mic = Mic.keep
    var look = Look.keep
    var hideOthers = false

    static let icons = ["briefcase.fill", "chevron.left.forwardslash.chevron.right", "person.2.fill", "play.rectangle.fill",
                        "paintbrush.pointed.fill", "book.fill", "gamecontroller.fill", "leaf.fill"]

    var summary: String {
        var parts = [apps.count == 1 ? L("1 app") : L("%d apps", apps.count)]
        if keepAwake { parts.append(L("acordado")) }
        if mic == .mute { parts.append(L("mic mudo")) }
        if look == .dark { parts.append(L("escuro")) }
        if look == .light { parts.append(L("claro")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Armazenamento e execução

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var profiles: [WorkProfile] = []
    /// Perfil sendo ativado (mostra o andamento na lista)
    @Published private(set) var activating: UUID?
    private var url: URL?
    private var timer: Timer?

    private init() {}

    /// Chamado na abertura do app (o modo captura usa `demo()`)
    func load(dir: URL) {
        url = dir.appendingPathComponent("profiles.json")
        if let url, let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([WorkProfile].self, from: data) {
            profiles = list
        }
    }

    func demo() {
        url = nil
        func app(_ name: String, _ bundle: String, _ path: String, _ frames: [CGRect]) -> ProfileApp {
            let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)?.path ?? path
            return ProfileApp(bundleID: bundle, name: FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""),
                       path: path, frames: frames)
        }
        profiles = [
            WorkProfile(name: L("Reunião"), icon: "person.2.fill", apps: [
                app("Calendar", "com.apple.iCal", "/System/Applications/Calendar.app", [CGRect(x: 0, y: 25, width: 720, height: 875)]),
                app("Notes", "com.apple.Notes", "/System/Applications/Notes.app", [CGRect(x: 720, y: 25, width: 720, height: 875)]),
            ], keepAwake: true, mic: .mute),
            WorkProfile(name: L("Foco"), icon: "leaf.fill", apps: [
                app("Safari", "com.apple.Safari", "/Applications/Safari.app", [CGRect(x: 0, y: 25, width: 960, height: 875)]),
                app("Music", "com.apple.Music", "/System/Applications/Music.app", [CGRect(x: 960, y: 25, width: 480, height: 875)]),
                app("Notes", "com.apple.Notes", "/System/Applications/Notes.app", [CGRect(x: 960, y: 450, width: 480, height: 450)]),
            ], look: .dark, hideOthers: true),
        ]
    }

    func profile(_ id: UUID) -> WorkProfile? { profiles.first { $0.id == id } }

    func upsert(_ p: WorkProfile) {
        if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p } else { profiles.append(p) }
        save()
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Captura

    /// Apps com janelas abertas agora, cada um com a posição das janelas. nil sem permissão de Acessibilidade.
    static func captureApps() -> [ProfileApp]? {
        guard AXIsProcessTrusted() else {
            ClipboardManager.requestAccessibility()
            return nil
        }
        let me = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isHidden, let bundle = app.bundleIdentifier, bundle != me,
                  let url = app.bundleURL else { return nil }
            let frames = windows(of: app.processIdentifier).compactMap { WindowManager.shared.frame(of: $0) }
            guard !frames.isEmpty else { return nil }
            return ProfileApp(bundleID: bundle, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                              path: url.path, frames: frames)
        }
    }

    /// Janelas normais e visíveis (sem painéis, diálogos ou minimizadas), da frente para trás
    private static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.filter { w in
            var sub: CFTypeRef?, min: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &sub)
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &min)
            return (sub as? String) == (kAXStandardWindowSubrole as String) && (min as? Bool) != true
        }
    }

    // MARK: Ativação

    func activate(_ p: WorkProfile, toolbox tb: Toolbox) {
        guard !p.apps.isEmpty else { return }
        guard AXIsProcessTrusted() else {
            ClipboardManager.requestAccessibility()
            return
        }
        timer?.invalidate()
        activating = p.id

        if p.keepAwake && !tb.keepAwake { tb.setKeepAwake(true) }
        if (p.mic == .mute && !tb.micMuted) || (p.mic == .unmute && tb.micMuted) { tb.toggleMic() }
        if (p.look == .dark && !tb.darkMode) || (p.look == .light && tb.darkMode) { tb.toggleDarkMode() }

        let wanted = Set(p.apps.map(\.bundleID))
        var failed: [String] = []
        for app in p.apps {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first {
                running.unhide()
            } else {
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) ?? URL(fileURLWithPath: app.path)
                guard FileManager.default.fileExists(atPath: url.path) else { failed.append(app.name); continue }
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
        }
        if p.hideOthers {
            let me = Bundle.main.bundleIdentifier
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                if let b = app.bundleIdentifier, !wanted.contains(b), b != me { app.hide() }
            }
        }

        // Apps recém-abertos demoram a criar as janelas: tenta de meio em meio segundo, por até 10 s
        var pending = p.apps.filter { !failed.contains($0.name) && !$0.frames.isEmpty }
        var tries = 0
        func place() {
            tries += 1
            pending.removeAll { app in
                guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first else { return false }
                let wins = Self.windows(of: running.processIdentifier)
                // Espera todas as janelas; depois de 3 s, aceita as que já abriram
                guard wins.count >= app.frames.count || (tries >= 6 && !wins.isEmpty) else { return false }
                for (w, f) in zip(wins, app.frames) { WindowManager.shared.setFrame(Self.fit(f), of: w) }
                return true
            }
            if pending.isEmpty || tries >= 20 { finish() }
        }
        func finish() {
            timer?.invalidate()
            timer = nil
            // O primeiro app do perfil fica na frente
            for app in p.apps.reversed() {
                NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first?.activate()
            }
            activating = nil
            let missing = failed + pending.map(\.name)
            if missing.isEmpty {
                HUD.show(icon: p.icon, color: .indigo, text: L("%@ ativado", p.name))
            } else {
                HUD.show(icon: "exclamationmark.triangle.fill", color: .orange,
                         text: L("%@: não deu para arrumar %@", p.name, missing.joined(separator: ", ")))
            }
        }
        place()
        if timer == nil, activating != nil, !pending.isEmpty {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in MainActor.assumeIsolated { place() } }
        }
    }

    /// Janela salva numa tela que não está mais conectada vai para a tela principal, do mesmo tamanho (cabendo)
    private static func fit(_ r: CGRect) -> CGRect {
        let wm = WindowManager.shared
        let areas = NSScreen.screens.map { wm.axFrame(of: $0.visibleFrame) }
        if areas.contains(where: { $0.contains(CGPoint(x: r.midX, y: r.midY)) }) { return r }
        guard let main = areas.first else { return r }
        let w = min(r.width, main.width), h = min(r.height, main.height)
        return CGRect(x: main.midX - w / 2, y: main.midY - h / 2, width: w, height: h)
    }
}

// MARK: Telas

/// Seção "Perfis" na aba Ações
struct ProfilesSection: View {
    @ObservedObject var store: ProfileStore
    let tb: Toolbox
    @Binding var editing: UUID?

    var body: some View {
        if store.profiles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Arrume as janelas do jeito que gosta e salve como perfil. Depois, um clique abre os apps e põe tudo no lugar."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(title: L("Salvar janelas atuais"), icon: "plus", primary: true) { create() }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(store.profiles.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52) }
                    row(p)
                }
                Rectangle().fill(Theme.cardStroke).frame(height: 0.5)
                Button { create() } label: {
                    Label(L("Salvar janelas atuais como perfil"), systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 4)
            .glass()
        }
    }

    private func row(_ p: WorkProfile) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [Color.indigo.opacity(0.85), .indigo], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: p.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(p.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: -6) {
                ForEach(p.apps.prefix(4)) { a in
                    Image(nsImage: AppIndex.icon(a.path)).resizable().frame(width: 20, height: 20)
                }
            }
            if store.activating == p.id {
                ProgressView().controlSize(.small).frame(width: 26)
            } else {
                IconButton(icon: "pencil", help: L("Editar perfil")) { editing = p.id }
                IconButton(icon: "play.fill", help: L("Ativar perfil")) { store.activate(p, toolbox: tb) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.activate(p, toolbox: tb) }
    }

    private func create() {
        guard let apps = ProfileStore.captureApps() else { return }
        guard !apps.isEmpty else { tb.show(L("Abra os apps e as janelas do perfil antes")); return }
        let p = WorkProfile(name: L("Perfil %d", store.profiles.count + 1), apps: apps)
        store.upsert(p)
        editing = p.id
    }
}

/// Editor de um perfil, no lugar da aba Ações
struct ProfileEditor: View {
    @ObservedObject var store: ProfileStore
    let tb: Toolbox
    @State var profile: WorkProfile
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { save(); onClose() } label: {
                        Label(L("Ações"), systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    Spacer()
                    PillButton(title: L("Ativar"), icon: "play.fill", primary: true) { save(); store.activate(profile, toolbox: tb) }
                }

                VStack(alignment: .leading, spacing: 10) {
                    TextField(L("Nome do perfil"), text: $profile.name)
                        .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                        .glassField()
                    HStack(spacing: 6) {
                        ForEach(WorkProfile.icons, id: \.self) { icon in
                            let on = profile.icon == icon
                            Button { profile.icon = icon } label: {
                                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(on ? .white : .secondary)
                                    .frame(width: 30, height: 26)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(on ? Color.indigo : Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                GlassSection(title: L("Apps e janelas")) {
                    ForEach(Array(profile.apps.enumerated()), id: \.element.id) { i, app in
                        if i > 0 { RowDivider(inset: 42) }
                        HStack(spacing: 10) {
                            Image(nsImage: AppIndex.icon(app.path)).resizable().frame(width: 22, height: 22)
                            Text(app.name).font(.system(size: 12.5))
                            Spacer()
                            Text(app.frames.count == 1 ? L("1 janela") : L("%d janelas", app.frames.count))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            IconButton(icon: "minus.circle", help: L("Tirar do perfil")) {
                                profile.apps.removeAll { $0.id == app.id }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    if !profile.apps.isEmpty { RowDivider() }
                    Button { recapture() } label: {
                        Label(L("Trocar pelas janelas de agora"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }

                GlassSection(title: L("Ao ativar")) {
                    ToggleRow(title: L("Manter acordado"), icon: "cup.and.saucer.fill", isOn: $profile.keepAwake)
                    RowDivider()
                    SettingRow(title: L("Microfone"), icon: "mic.fill") {
                        Picker("", selection: $profile.mic) {
                            Text(L("Não mexer")).tag(WorkProfile.Mic.keep)
                            Text(L("Mutar")).tag(WorkProfile.Mic.mute)
                            Text(L("Ligar")).tag(WorkProfile.Mic.unmute)
                        }
                        .labelsHidden().fixedSize()
                    }
                    RowDivider()
                    SettingRow(title: L("Aparência"), icon: "circle.lefthalf.filled") {
                        Picker("", selection: $profile.look) {
                            Text(L("Não mexer")).tag(WorkProfile.Look.keep)
                            Text(L("Claro")).tag(WorkProfile.Look.light)
                            Text(L("Escuro")).tag(WorkProfile.Look.dark)
                        }
                        .labelsHidden().fixedSize()
                    }
                    RowDivider()
                    ToggleRow(title: L("Esconder os outros apps"), icon: "eye.slash", isOn: $profile.hideOthers)
                }

                Button(role: .destructive) {
                    store.delete(profile.id)
                    onClose()
                } label: {
                    Label(L("Apagar perfil"), systemImage: "trash").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(.red).padding(.leading, 4)
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .noLiquidGlass()
        .scrollIndicators(.never)
        .onChange(of: profile) { _, p in store.upsert(p) }
    }

    private func save() { store.upsert(profile) }

    private func recapture() {
        guard let apps = ProfileStore.captureApps() else { return }
        guard !apps.isEmpty else { tb.show(L("Abra os apps e as janelas do perfil antes")); return }
        profile.apps = apps
    }
}
