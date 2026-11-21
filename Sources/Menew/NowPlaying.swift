import AppKit
import SwiftUI

/// O que está tocando no Spotify ou no Música, para o painel do notch.
/// Os dois apps avisam cada troca de faixa por notificações do próprio macOS, então ler não pede permissão nem rede.
/// Os botões (tocar/pausar, anterior, seguinte) mandam AppleScript para o app: na primeira vez o macOS pede para
/// o Menew controlá-lo. Sem capa: a do Spotify teria que ser baixada, e o Menew não faz essa chamada.
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()
    static let key = "notch.nowPlaying"
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    enum Source: String, CaseIterable {
        case spotify, music

        var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }

        /// Avisos que o app manda a cada troca de faixa, pausa ou parada
        var notification: Notification.Name {
            .init(self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo")
        }

        var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

        /// O nome que o macOS mostra (Música, Musik, 音乐…)
        var name: String {
            appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
                ?? (self == .spotify ? "Spotify" : "Music")
        }

        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    struct Track: Equatable {
        let source: Source
        let title: String
        let artist: String
        let album: String
        var playing: Bool
    }

    enum Command { case playPause, next, previous }

    @Published private(set) var track: Track?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let center = DistributedNotificationCenter.default()
        for source in Source.allCases {
            center.addObserver(forName: source.notification, object: nil, queue: .main) { n in
                let info = n.userInfo ?? [:]
                let state = info["Player State"] as? String ?? ""
                let title = info["Name"] as? String ?? ""
                let artist = info["Artist"] as? String ?? ""
                let album = info["Album"] as? String ?? ""
                MainActor.assumeIsolated {
                    NowPlaying.shared.update(source, state: state, title: title, artist: artist, album: album)
                }
            }
        }
        // O app fechou: some do painel
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
            let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if let t = NowPlaying.shared.track, t.source.bundleID == id { NowPlaying.shared.track = nil }
            }
        }
        readCurrent()
    }

    private func update(_ source: Source, state: String, title: String, artist: String, album: String) {
        guard state != "Stopped", !title.isEmpty else {
            if track?.source == source { track = nil }
            return
        }
        let playing = state == "Playing"
        // Um app pausado não tira do painel o outro que está tocando
        if !playing, let t = track, t.source != source, t.playing { return }
        track = Track(source: source, title: title, artist: artist, album: album, playing: playing)
    }

    /// Ao abrir o Menew, a faixa que já estava tocando (os avisos só vêm na próxima troca).
    /// Só pergunta a um app aberto e que o Menew já pode controlar: nunca abre o app nem mostra o pedido de permissão.
    private func readCurrent() {
        for source in Source.allCases where source.isRunning && Self.allowed(source) {
            let script = """
            tell application id "\(source.bundleID)"
                if player state is stopped then return ""
                set t to current track
                return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((player state is playing) as text)
            end tell
            """
            var err: NSDictionary?
            guard let out = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue, err == nil else { continue }
            let parts = out.components(separatedBy: "\n")
            guard parts.count == 4, !parts[0].isEmpty else { continue }
            update(source, state: parts[3] == "true" ? "Playing" : "Paused", title: parts[0], artist: parts[1], album: parts[2])
        }
    }

    /// O Menew já tem permissão para controlar o app? Pergunta ao macOS sem mostrar o pedido.
    private static func allowed(_ source: Source) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: source.bundleID)
        guard let desc = target.aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false) == noErr
    }

    func send(_ command: Command) {
        guard let t = track, t.source.isRunning else { return }
        let verb = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        var err: NSDictionary?
        NSAppleScript(source: "tell application id \"\(t.source.bundleID)\" to \(verb)")?.executeAndReturnError(&err)
        if let err {
            // -1743: a pessoa não deixou o Menew controlar o app. Os Ajustes mostram onde liberar.
            if (err[NSAppleScript.errorNumber] as? Int) == -1743,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        // O app avisa a mudança logo em seguida; até lá, o botão já mostra o novo estado
        if command == .playPause { track?.playing.toggle() }
    }

    /// Traz o app para a frente
    func openApp() {
        guard let t = track, let url = t.source.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Uma linha do painel do notch: o ícone do app, a faixa e os botões
struct NowPlayingRow: View {
    let track: NowPlaying.Track
    var onOpen: () -> Void = {}
    var onCommand: (NowPlaying.Command) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    icon.frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            if track.playing {
                                Image(systemName: "waveform").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
                                    .symbolEffect(.variableColor.iterative, options: .repeating)
                            }
                            Text(track.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        }
                        Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Abrir %@", track.source.name))
            control("backward.fill", L("Faixa anterior")) { onCommand(.previous) }
            control(track.playing ? "pause.fill" : "play.fill", L("Tocar/pausar"), big: true) { onCommand(.playPause) }
            control("forward.fill", L("Próxima faixa")) { onCommand(.next) }
        }
        .frame(height: 38)
    }

    @ViewBuilder private var icon: some View {
        if let url = track.source.appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "music.note").font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 7).fill(.pink.gradient))
        }
    }

    private func control(_ icon: String, _ help: String, big: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? 13 : 11, weight: .semibold))
                .frame(width: big ? 32 : 28, height: big ? 32 : 28)
                .background(Circle().fill(.white.opacity(big ? 0.18 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
