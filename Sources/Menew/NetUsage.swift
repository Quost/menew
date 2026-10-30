import AppKit
import SwiftUI

struct NetApp: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let down: Double
    let up: Double
    var icon: NSImage?
}

/// Quem está usando a rede, por app, lido do `nettop` do macOS. Cada leitura custa ~1 s de CPU,
/// então só roda quando você abre a lista e para quando ela some.
@MainActor
final class NetUsage: ObservableObject {
    static let shared = NetUsage()

    @Published var expanded = false { didSet { expanded ? start() : stop() } }
    @Published private(set) var apps: [NetApp] = []
    @Published private(set) var loading = false

    private var timer: Timer?
    private var demo = false

    private func start() {
        guard !demo, timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
    }

    private func sample() {
        guard !loading else { return }
        loading = apps.isEmpty
        Task {
            let out = await Task.detached {
                Shell.run("/usr/bin/nettop", ["-P", "-n", "-x", "-L", "2", "-d", "-s", "1", "-J", "bytes_in,bytes_out"])
            }.value
            loading = false
            guard timer != nil else { return }
            apps = Self.parse(out)
        }
    }

    /// A segunda amostra traz o que passou em 1 segundo. Ajudantes ("Google Chrome Helper") contam para o app.
    static func parse(_ out: String) -> [NetApp] {
        var totals: [String: (Double, Double)] = [:]
        var block = 0
        for line in out.split(separator: "\n") {
            if line.hasPrefix(",bytes_in") { block += 1; continue }
            guard block == 2 else { continue }
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3, let down = Double(cols[1]), let up = Double(cols[2]), down + up > 0 else { continue }
            var name = String(cols[0])
            if let dot = name.lastIndex(of: "."), Int(name[name.index(after: dot)...]) != nil { name = String(name[..<dot]) }
            name = name.components(separatedBy: " Helper").first ?? name
            name = name.trimmingCharacters(in: .whitespaces)
            let t = totals[name] ?? (0, 0)
            totals[name] = (t.0 + down, t.1 + up)
        }
        let running = NSWorkspace.shared.runningApplications
        return totals.map { name, t in
            let app = running.first { $0.localizedName == name }
            return NetApp(name: name, down: t.0, up: t.1, icon: app?.icon)
        }
        .sorted { $0.down + $0.up > $1.down + $1.up }
        .prefix(6).map { $0 }
    }

    /// Para as capturas de tela
    func showDemo() {
        demo = true
        expanded = true
        apps = [
            NetApp(name: "Safari", down: 2_400_000, up: 86_000, icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app")),
            NetApp(name: "Music", down: 320_000, up: 4_000, icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")),
            NetApp(name: "Mail", down: 48_000, up: 12_000, icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Mail.app")),
        ]
    }
}

/// Dentro do cartão Internet: "Quem está usando a rede?"
struct NetAppsSection: View {
    @ObservedObject var usage = NetUsage.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                usage.expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.download)
                    Text(L("Apps usando a rede")).font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    if usage.expanded, usage.loading { ProgressView().controlSize(.mini) }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(usage.expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if usage.expanded {
                if usage.apps.isEmpty {
                    if !usage.loading {
                        Text(L("Nenhum app usando a rede agora.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(usage.apps) { app in
                        HStack(spacing: 8) {
                            Group {
                                if let icon = app.icon { Image(nsImage: icon).resizable() }
                                else { Image(systemName: "gearshape.fill").foregroundStyle(.secondary) }
                            }
                            .frame(width: 16, height: 16)
                            Text(app.name).font(.system(size: 11.5)).lineLimit(1)
                            Spacer(minLength: 4)
                            rate("arrow.down", app.down, Theme.download)
                            rate("arrow.up", app.up, Theme.upload)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
        .onDisappear { usage.stop(); if usage.expanded { usage.expanded = false } }
    }

    private func rate(_ icon: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
            Text(Fmt.shortRate(value)).font(.system(size: 10.5, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(width: 62, alignment: .trailing)
    }
}
