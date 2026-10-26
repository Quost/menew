import SwiftUI
import ServiceManagement
import ApplicationServices

enum Tab: String, CaseIterable {
    case system = "Sistema", clipboard = "Clipboard", actions = "Ações", notes = "Notas", settings = "Ajustes"
    static let visible: [Tab] = [.system, .clipboard, .actions, .notes]
    var icon: String {
        switch self {
        case .system: "gauge.with.dots.needle.67percent"
        case .clipboard: "doc.on.clipboard"
        case .actions: "bolt.fill"
        case .notes: "note.text"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class PopoverState: ObservableObject {
    @Published var tab: Tab = .system
}

struct MainView: View {
    @ObservedObject var nav: PopoverState
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var toolbox: Toolbox
    @ObservedObject var internet: InternetInfo
    @ObservedObject var notes: NotesStore
    let clipState: ClipListState
    var onPickClip: (ClipItem, Bool) -> Void

    @Namespace private var tabNS

    var body: some View {
        VStack(spacing: 0) {
            header
            if nav.tab != .settings { tabBar }

            Group {
                switch nav.tab {
                case .system: SystemView(m: monitor, net: internet)
                case .clipboard: ClipboardTabView(manager: clipboard, state: clipState, onActivate: onPickClip)
                case .actions: ActionsView(tb: toolbox, clipboard: clipboard)
                case .notes: NotesView(store: notes)
                case .settings: SettingsView(clipboard: clipboard)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 400, height: 600)
        .background(Theme.windowFill)
        .overlay(alignment: .bottom) {
            if let t = toolbox.toast {
                Label(t, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.regularMaterial).shadow(color: .black.opacity(0.15), radius: 8, y: 2))
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toolbox.toast)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if nav.tab == .settings {
                IconButton(icon: "chevron.left", help: "Voltar") { nav.tab = .system }
                Text("Ajustes").font(.system(size: 15, weight: .semibold))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.brand)
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                .shadow(color: Theme.violet.opacity(0.35), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Menew").font(.system(size: 14, weight: .bold, design: .rounded))
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))).prefix(1).uppercased() + ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))).dropFirst())
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if nav.tab != .settings {
                IconButton(icon: "gearshape", help: "Ajustes") { nav.tab = .settings }
            }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.visible, id: \.self) { t in
                let on = nav.tab == t
                Button {
                    withAnimation(.spring(duration: 0.28)) { nav.tab = t }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.icon).font(.system(size: 11, weight: .semibold))
                        Text(t.rawValue).font(.system(size: 11.5, weight: on ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "tab", in: tabNS)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 14).padding(.bottom, 12)
    }
}

// MARK: Sistema

struct SystemView: View {
    @ObservedObject var m: SystemMonitor
    @ObservedObject var net: InternetInfo

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                overview
                cpuCard
                networkCard
                if !net.devices.isEmpty { devicesCard }
                processesCard
                HStack(spacing: 10) {
                    MiniStat(icon: "clock.fill", color: .indigo, title: "Ligado há", value: Fmt.duration(m.uptime))
                    MiniStat(icon: "thermometer.medium", color: thermalColor, title: "Temperatura", value: thermalText)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .scrollIndicators(.never)
        .onAppear {
            m.wantsProcesses = true
            m.refreshProcesses()
            net.refreshIfNeeded()
        }
        .onDisappear { m.wantsProcesses = false }
    }

    private var overview: some View {
        HStack(spacing: 0) {
            RingStat(title: "CPU", fraction: m.cpu, color: Theme.load(m.cpu, base: Theme.cpu),
                     detail: "\(m.cores) núcleos")
            RingStat(title: "Memória", fraction: m.memFraction, color: Theme.load(m.memFraction, base: Theme.memory),
                     detail: "\(Fmt.memShort(m.memUsed)) de \(Fmt.memShort(m.memTotal))")
            RingStat(title: "Disco", fraction: m.diskFraction, color: Theme.load(m.diskFraction, base: Theme.disk),
                     detail: "\(Fmt.bytes(m.diskFree)) livres")
            if let b = m.battery {
                RingStat(title: "Bateria", fraction: Double(b.percent) / 100,
                         color: b.percent <= 20 && !b.onAC ? .red : Theme.battery,
                         detail: batteryText(b), icon: b.charging ? "bolt.fill" : nil)
            }
        }
        .card(padding: 14)
    }

    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Processador", icon: "cpu", color: Theme.cpu) {
                Text("últimos 2 min").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.pct(m.cpu)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("em uso").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(width: 72, alignment: .leading)
                Sparkline(values: m.cpuHistory, color: Theme.load(m.cpu, base: Theme.cpu))
                    .frame(height: 46)
            }
        }
        .card()
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Internet", icon: "wifi", color: Theme.download)
            HStack(spacing: 10) {
                NetStat(title: "Download", icon: "arrow.down", color: Theme.download, value: m.netIn, history: m.netInHistory)
                NetStat(title: "Upload", icon: "arrow.up", color: Theme.upload, value: m.netOut, history: m.netOutHistory)
            }
            HStack(spacing: 8) {
                CopyPill(label: "IP local", value: m.localIP)
                CopyPill(label: "IP público", value: net.publicIP ?? "…")
            }
            speedTest
        }
        .card()
    }

    @ViewBuilder private var speedTest: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch net.speed {
            case .idle:
                HStack {
                    Text("Quer saber a velocidade real da sua conexão?").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    PillButton(title: "Testar", icon: "speedometer", primary: true) { net.runSpeedTest() }
                }
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Medindo velocidade… leva uns 20 segundos").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                }
            case .failed:
                HStack {
                    Text("Não deu para medir agora.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    PillButton(title: "Tentar de novo", icon: "arrow.clockwise") { net.runSpeedTest() }
                }
            case .done(let r):
                HStack(spacing: 0) {
                    SpeedValue(title: "Download", value: String(format: "%.0f", r.down), unit: "Mbps", color: Theme.download)
                    SpeedValue(title: "Upload", value: String(format: "%.0f", r.up), unit: "Mbps", color: Theme.upload)
                    SpeedValue(title: "Latência", value: String(format: "%.0f", r.latency), unit: "ms", color: .orange)
                    IconButton(icon: "arrow.clockwise", help: "Testar de novo") { net.runSpeedTest() }
                }
                Text(r.quality).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Dispositivos", icon: "dot.radiowaves.left.and.right", color: .blue)
            ForEach(net.devices) { d in
                HStack(spacing: 10) {
                    Image(systemName: d.icon).font(.system(size: 15)).frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                    Text(d.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Spacer()
                    ForEach(d.levels, id: \.label) { l in
                        BatteryPill(label: l.label, percent: l.percent)
                    }
                }
            }
        }
        .card()
    }

    private var processesCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            CardHeader(title: "Quem está usando a CPU", icon: "list.bullet", color: .secondary) {
                Button("Monitor de Atividade") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.indigo)
            }
            if m.topProcesses.isEmpty {
                Text("Carregando…").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(m.topProcesses.prefix(5)) { p in
                HStack(spacing: 8) {
                    Group {
                        if let icon = AppIcons.icon(forProcess: p.name) {
                            Image(nsImage: icon).resizable()
                        } else {
                            Image(systemName: "gearshape.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(p.name).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Fmt.mem(p.memKB * 1024)).font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                    UsageBar(fraction: min(p.cpu / 100, 1), color: Theme.cpu, height: 4).frame(width: 44)
                    Text(String(format: "%.0f%%", p.cpu)).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .card()
    }

    private func batteryText(_ b: BatteryInfo) -> String {
        let t = b.minutesLeft.map { "\($0 / 60)h\(String(format: "%02d", $0 % 60))" }
        if b.charging { return t.map { "cheia em \($0)" } ?? "carregando" }
        if b.onAC { return "na tomada" }
        return t.map { "restam \($0)" } ?? "na bateria"
    }

    private var thermalText: String {
        switch m.thermal {
        case .nominal: "Normal"
        case .fair: "Morno"
        case .serious: "Quente"
        case .critical: "Crítico"
        @unknown default: "—"
        }
    }

    private var thermalColor: Color {
        switch m.thermal {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        default: .red
        }
    }
}

struct RingStat: View {
    let title: String
    let fraction: Double
    let color: Color
    let detail: String
    var icon: String? = nil

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Ring(fraction: fraction, color: color, lineWidth: 6)
                VStack(spacing: -1) {
                    if let icon { Image(systemName: icon).font(.system(size: 8, weight: .bold)).foregroundStyle(color) }
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(Int((fraction * 100).rounded()))")
                            .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("%").font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 58, height: 58)
            VStack(spacing: 1) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct NetStat: View {
    let title: String
    let icon: String
    let color: Color
    let value: Double
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white).frame(width: 15, height: 15).background(Circle().fill(color))
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(Fmt.rate(value)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
            Sparkline(values: history, color: color, maxValue: nil).frame(height: 24)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

struct CopyPill: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(value).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10)).foregroundStyle(copied ? .green : .secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copiar")
    }
}

struct SpeedValue: View {
    let title: String, value: String, unit: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(color)
                Text(unit).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BatteryPill: View {
    let label: String
    let percent: Int
    var body: some View {
        HStack(spacing: 4) {
            if !label.isEmpty { Text(label).foregroundStyle(.secondary) }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1).fill(percent <= 20 ? Color.red : Theme.battery)
                    .frame(width: max(2, 16 * CGFloat(percent) / 100)).padding(2)
            }
            .frame(width: 20, height: 10)
            Text("\(percent)%").monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
    }
}

struct MiniStat: View {
    let icon: String, color: Color, title: String, value: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 12.5, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .card(padding: 10)
    }
}

// MARK: Ações

struct ActionsView: View {
    @ObservedObject var tb: Toolbox
    @ObservedObject var cleaning: CleaningController
    let clipboard: ClipboardManager

    init(tb: Toolbox, clipboard: ClipboardManager) {
        self.tb = tb
        self.cleaning = tb.cleaning
        self.clipboard = clipboard
    }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                group("Limpeza") {
                    ActionTile(icon: "keyboard", color: .teal, title: "Limpar teclado", subtitle: "trava por 2 min",
                               on: cleaning.keyboardLocked) {
                        if !cleaning.lockKeyboard() { tb.show("Libere o Menew em Acessibilidade") }
                    }
                    ActionTile(icon: "sparkles.tv", color: .cyan, title: "Limpar tela", subtitle: "tela preta") {
                        cleaning.blackScreen()
                    }
                    ActionTile(icon: "trash", color: .red, title: "Esvaziar lixeira") { tb.emptyTrash() }
                }
                group("Energia") {
                    ActionTile(icon: "cup.and.saucer.fill", color: .orange, title: "Manter acordado",
                               subtitle: tb.keepAwake ? "ligado" : nil, on: tb.keepAwake) {
                        tb.setKeepAwake(!tb.keepAwake)
                    }
                    ActionTile(icon: "timer", color: .orange, title: "Acordado 1h") {
                        tb.setKeepAwake(true, minutes: 60); tb.show("Acordado por 1 hora")
                    }
                    ActionTile(icon: "lock.fill", color: .gray, title: "Bloquear tela") { tb.lockScreen() }
                }
                group("Finder") {
                    ActionTile(icon: "eye", color: .blue, title: "Arquivos ocultos", on: tb.hiddenFiles) { tb.toggleHiddenFiles() }
                    ActionTile(icon: "menubar.dock.rectangle", color: .indigo, title: "Ocultar mesa",
                               on: tb.desktopIconsHidden) { tb.toggleDesktopIcons() }
                    ActionTile(icon: "eject.fill", color: .mint, title: "Ejetar discos") { tb.ejectAll() }
                }
                group("Ferramentas") {
                    ActionTile(icon: "circle.lefthalf.filled", color: .purple, title: "Modo escuro") { tb.toggleDarkMode() }
                    ActionTile(icon: "camera.viewfinder", color: .pink, title: "Print", subtitle: "vai pro clipboard") {
                        tb.screenshotToClipboard()
                    }
                    ActionTile(icon: "eyedropper.halffull", color: Theme.violet, title: "Conta-gotas", subtitle: "copia o hex") {
                        tb.pickColor(clipboard: clipboard)
                    }
                    ActionTile(icon: "textformat", color: .brown, title: "Limpar formatação") { tb.plainTextClipboard() }
                    ActionTile(icon: "chart.bar.xaxis", color: .green, title: "Monitor") {
                        tb.open("/System/Applications/Utilities/Activity Monitor.app")
                    }
                    ActionTile(icon: "terminal.fill", color: .black, title: "Terminal") {
                        tb.open("/System/Applications/Utilities/Terminal.app")
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .scrollIndicators(.never)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 2)
            LazyVGrid(columns: cols, spacing: 8) { content() }
        }
    }
}

struct ActionTile: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    var on = false
    let action: () -> Void
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.gradient)
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                .shadow(color: color.opacity(on ? 0.5 : 0.25), radius: on ? 7 : 3, y: 2)
                .overlay(alignment: .topTrailing) {
                    if on {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white, .green)
                            .background(Circle().fill(Theme.windowFill).padding(1))
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                VStack(spacing: 1) {
                    Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? AnyShapeStyle(color.opacity(0.12)) : AnyShapeStyle(Theme.cardFill))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(hover ? 0.05 : 0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(on ? color.opacity(0.7) : Theme.cardStroke, lineWidth: on ? 1.5 : 0.5)
            )
            .scaleEffect(pressed ? 0.96 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(.spring(duration: 0.25), value: on)
    }
}

// MARK: Notas

struct NotesView: View {
    @ObservedObject var store: NotesStore
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if store.text.isEmpty {
                    Text("Anote qualquer coisa…\nSalva sozinho, fica aqui até você apagar.")
                        .font(.system(size: 13)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $store.text)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
            }
            .card(padding: 10)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.icloud").foregroundStyle(.green)
                Text("Salvo · \(store.text.count) caracteres").foregroundStyle(.secondary)
                Spacer()
                PillButton(title: "Copiar", icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.text, forType: .string)
                }
                IconButton(icon: "trash", help: "Apagar notas") { confirmClear = true }
            }
            .font(.system(size: 11))
            .confirmationDialog("Apagar todas as notas?", isPresented: $confirmClear) {
                Button("Apagar", role: .destructive) { store.text = "" }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
    }
}

// MARK: Ajustes

struct SettingsView: View {
    @ObservedObject var clipboard: ClipboardManager
    @AppStorage("menuBarStyle") private var style = MenuBarStyle.cpuRam.rawValue
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("maxItems") private var maxItems = 300
    @AppStorage("ignoreConcealed") private var ignoreConcealed = true
    @AppStorage("paused") private var paused = false
    @AppStorage("ignoredApps") private var ignoredApps = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Aparência") {
                Picker("Tema", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            Section("Barra de menus") {
                Picker("Mostrar", selection: $style) {
                    ForEach(MenuBarStyle.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Abrir ao iniciar o Mac", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }
            Section("Permissões") {
                HStack {
                    Label("Acessibilidade", systemImage: axTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(axTrusted ? .green : .orange)
                    Spacer()
                    if !axTrusted {
                        Button("Permitir") {
                            ClipboardManager.requestAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { axTrusted = AXIsProcessTrusted() }
                        }
                    }
                }
                Text("Usada para colar automaticamente e para travar o teclado na limpeza.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Clipboard") {
                Toggle("Colar automaticamente ao escolher", isOn: $autoPaste)
                Toggle("Pausar captura", isOn: $paused)
                Toggle("Ignorar senhas (1Password, Keychain…)", isOn: $ignoreConcealed)
                Stepper("Guardar \(maxItems) itens", value: $maxItems, in: 50...2000, step: 50)
                TextField("Ignorar apps", text: $ignoredApps, prompt: Text("bundle IDs separados por vírgula"))
                Button("Limpar histórico (mantém fixados)", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Apagar todo o histórico não fixado?", isPresented: $confirmClear) {
                        Button("Apagar", role: .destructive) { clipboard.clear() }
                    }
            }
            Section("Atalhos") {
                LabeledContent("Histórico do clipboard") { Keycap(text: "⌘⇧V") }
                LabeledContent("Abrir este menu") { Keycap(text: "⌥⌘M") }
            }
            Section {
                HStack {
                    Text("Menew \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sair do Menew") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { axTrusted = AXIsProcessTrusted() }
    }
}

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    var label: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Escuro"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum MenuBarStyle: String, CaseIterable {
    case icon, cpu, cpuRam, network, all
    var label: String {
        switch self {
        case .icon: "Só o ícone"
        case .cpu: "CPU"
        case .cpuRam: "CPU + RAM"
        case .network: "Rede"
        case .all: "CPU + RAM + Rede"
        }
    }
}
