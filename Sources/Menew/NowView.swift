import SwiftUI

/// Aba "Agora": o que importa em 2 segundos. Busca da paleta, os números do Mac numa linha, se está tudo bem,
/// timers em andamento, relógios e os favoritos. O resto do Sistema fica em "Detalhes do Mac".
struct NowView: View {
    @ObservedObject var nav: PopoverState
    @ObservedObject var m: SystemMonitor
    @ObservedObject var tb: Toolbox
    @ObservedObject var timers = TimerStore.shared
    @ObservedObject var focus = FocusTimer.shared
    let clipboard: ClipboardManager
    var openCleaner: () -> Void
    @AppStorage(Module.clipboard.key) private var clipboardOn = true
    @AppStorage(Module.actions.key) private var actionsOn = true
    @AppStorage(Module.notes.key) private var notesOn = true

    private var app: AppDelegate? { NSApp.delegate as? AppDelegate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                search
                metrics
                status
                if focus.isRunning || !timers.active.isEmpty { countdowns }
                WorldClockCard()
                if actionsOn { FavoritesSection(tb: tb, clipboard: clipboard, openCleaner: openCleaner) }
                if !clipboardOn || !actionsOn || !notesOn {
                    Button { SettingsWindow.shared.show(.general) } label: {
                        Label(L("Adicionar recursos…"), systemImage: "plus.circle")
                            .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .noLiquidGlass()
        .scrollIndicators(.never)
        .onAppear { tb.refresh() }
    }

    // A paleta faz tudo: apps, ações, contas, IA
    private var search: some View {
        Button { app?.palette.show() } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(L("Buscar, fazer ou perguntar…")).foregroundStyle(.secondary)
                Spacer()
                Text(Shortcut.load(HotKeyCenter.paletteKey, default: .paletteDefault).display)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            tile(L("CPU"), Fmt.pct(m.cpu), m.cpu, Theme.load(m.cpu, base: Theme.cpu))
            tile(L("Memória"), Fmt.pct(m.memFraction), m.memFraction,
                 m.memPressure == .normal ? Theme.memory : m.memPressure == .warning ? .orange : .red)
            tile(L("livres"), Self.shortBytes(m.diskFree), m.diskFraction, m.diskFraction > 0.92 ? .red : Theme.disk)
            if let b = m.battery {
                tile(b.charging ? L("carregando") : L("Bateria"), "\(b.percent)%", Double(b.percent) / 100,
                     b.percent <= 20 && !b.onAC ? .red : Theme.battery)
            } else {
                tile("↓ " + L("Rede"), Fmt.shortRate(m.netIn), min(1, m.netIn / 50_000_000), Theme.download)
            }
        }
    }

    /// "748 GB", "1,2 TB": sem casas decimais que não cabem no quadradinho
    static func shortBytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = b >= 1_000_000_000_000 ? [.useTB] : [.useGB]
        f.isAdaptive = b >= 1_000_000_000_000
        return f.string(fromByteCount: b).replacingOccurrences(of: #"[.,]\d+ GB"#, with: " GB", options: .regularExpression)
    }

    private func tile(_ title: String, _ value: String, _ fraction: Double, _ color: Color) -> some View {
        Button { nav.tab = .system } label: {
            VStack(spacing: 5) {
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(color.gradient).frame(width: max(3, g.size.width * min(1, max(0, fraction))))
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 8).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .card(padding: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Detalhes do Mac"))
    }

    /// Uma frase: tudo bem, ou o que pede atenção (e o atalho para o diagnóstico)
    private var problems: [String] {
        var p: [String] = []
        if m.memPressure != .normal { p.append(L("memória no limite")) }
        if m.cpu > 0.85 { p.append(L("CPU alta")) }
        if m.diskTotal > 0, m.diskFree < 10_000_000_000 { p.append(L("pouco espaço")) }
        if m.thermal == .serious || m.thermal == .critical { p.append(L("Mac quente")) }
        if let b = m.battery, !b.onAC, b.percent <= 20 { p.append(L("bateria baixa")) }
        return p
    }

    private var status: some View {
        HStack(spacing: 8) {
            Image(systemName: problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(problems.isEmpty ? .green : .orange)
            Text(problems.isEmpty ? L("Tudo normal") : problems.joined(separator: ", ").prefix(1).uppercased() + problems.joined(separator: ", ").dropFirst())
                .font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            if !problems.isEmpty {
                Button(L("Por quê?")) { DiagnosisWindow.shared.show(m) }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            Button(L("Detalhes do Mac")) { nav.tab = .system }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 4)
    }

    private var countdowns: some View {
        VStack(spacing: 6) {
            if focus.isRunning {
                row(icon: focus.phase == .rest ? "cup.and.saucer.fill" : "scope", color: focus.phase == .rest ? .green : .orange,
                    title: focus.phase == .rest ? L("Pausa") : L("Foco"), end: focus.endsAt) { focus.stop() }
            }
            ForEach(timers.active) { t in
                row(icon: t.isAlarm ? "alarm.fill" : "hourglass", color: .blue, title: t.label.isEmpty ? L("Timer") : t.label, end: t.end) {
                    timers.cancel(t.id)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .card(padding: 0)
    }

    private func row(icon: String, color: Color, title: String, end: Date, stop: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color).frame(width: 18)
            Text(title).font(.system(size: 12.5)).lineLimit(1)
            Spacer(minLength: 4)
            Text(end, style: .timer).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
            Button(action: stop) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.tertiary).help(L("Parar"))
        }
    }
}
