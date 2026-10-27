import SwiftUI
import ServiceManagement
import ApplicationServices

enum Tab: String, CaseIterable {
    case system = "Sistema", clipboard = "Clipboard", actions = "Ações", notes = "Notas", settings = "Ajustes"
    case cleaner = "Liberar espaço"
    static let visible: [Tab] = [.system, .clipboard, .actions, .notes]
    var icon: String {
        switch self {
        case .system: "gauge.with.dots.needle.67percent"
        case .clipboard: "doc.on.clipboard"
        case .actions: "bolt.fill"
        case .notes: "note.text"
        case .settings: "gearshape"
        case .cleaner: "sparkles"
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
    @ObservedObject var cleaner: Cleaner
    @ObservedObject var updater: UpdaterModel
    let clipState: ClipListState
    var onPickClip: (ClipItem, Bool) -> Void

    @Namespace private var tabNS
    @AppStorage("language") private var language = "auto"

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isSubpage { tabBar }

            Group {
                switch nav.tab {
                case .system: SystemView(m: monitor, net: internet)
                case .clipboard: ClipboardTabView(manager: clipboard, state: clipState, onActivate: onPickClip)
                case .actions: ActionsView(tb: toolbox, clipboard: clipboard) { nav.tab = .cleaner }
                case .cleaner: CleanerView(cleaner: cleaner, monitor: monitor)
                case .notes: NotesView(store: notes)
                case .settings: SettingsView(clipboard: clipboard, updater: updater)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 400, height: 600)
        .background(Theme.popoverFill)
        .id(language)
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

    /// Telas abertas por botão (com "voltar"), fora da barra de abas
    private var isSubpage: Bool { nav.tab == .settings || nav.tab == .cleaner }

    private var header: some View {
        HStack(spacing: 10) {
            if isSubpage {
                IconButton(icon: "chevron.left", help: L("Voltar")) { nav.tab = nav.tab == .cleaner ? .actions : .system }
                Text(L(nav.tab.rawValue)).font(.system(size: 15, weight: .semibold))
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
                        Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale)).prefix(1).uppercased() + ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale)).dropFirst())
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if !isSubpage {
                IconButton(icon: "gearshape", help: L("Ajustes")) { nav.tab = .settings }
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
                        Text(L(t.rawValue)).font(.system(size: 11.5, weight: on ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .background {
                        if on {
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "tab", in: tabNS)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glass(in: Capsule())
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
                MemoryCard(m: m)
                if let b = m.battery, let h = m.batteryHealth { BatteryCard(battery: b, health: h) }
                networkCard
                if !net.devices.isEmpty { devicesCard }
                processesCard
                HStack(spacing: 10) {
                    MiniStat(icon: "clock.fill", color: .indigo, title: L("Ligado há"), value: Fmt.duration(m.uptime))
                    MiniStat(icon: "thermometer.medium", color: thermalColor, title: L("Temperatura"), value: thermalText)
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
                     detail: L("%d núcleos", m.cores))
            RingStat(title: L("Memória"), fraction: m.memFraction, color: Theme.load(m.memFraction, base: Theme.memory),
                     detail: L("%@ de %@", Fmt.memShort(m.memUsed), Fmt.memShort(m.memTotal)))
            RingStat(title: L("Disco"), fraction: m.diskFraction, color: Theme.load(m.diskFraction, base: Theme.disk),
                     detail: L("%@ livres", Fmt.bytes(m.diskFree)))
            if let b = m.battery {
                RingStat(title: L("Bateria"), fraction: Double(b.percent) / 100,
                         color: b.percent <= 20 && !b.onAC ? .red : Theme.battery,
                         detail: batteryText(b), icon: b.charging ? "bolt.fill" : nil)
            }
        }
        .card(padding: 14)
    }

    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: L("Processador"), icon: "cpu", color: Theme.cpu) {
                Text(L("últimos 2 min")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.pct(m.cpu)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(L("em uso")).font(.system(size: 11)).foregroundStyle(.secondary)
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
            CardHeader(title: L("Internet"), icon: "wifi", color: Theme.download)
            HStack(spacing: 10) {
                NetStat(title: L("Download"), icon: "arrow.down", color: Theme.download, value: m.netIn, history: m.netInHistory)
                NetStat(title: L("Upload"), icon: "arrow.up", color: Theme.upload, value: m.netOut, history: m.netOutHistory)
            }
            HStack(spacing: 8) {
                CopyPill(label: L("IP local"), value: m.localIP)
                CopyPill(label: L("IP público"), value: net.publicIP ?? "…")
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
                    Text(L("Quer saber a velocidade real da sua conexão?")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    PillButton(title: L("Testar"), icon: "speedometer", primary: true) { net.runSpeedTest() }
                }
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Medindo velocidade… leva uns 20 segundos")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                }
            case .failed:
                HStack {
                    Text(L("Não deu para medir agora.")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    PillButton(title: L("Tentar de novo"), icon: "arrow.clockwise") { net.runSpeedTest() }
                }
            case .done(let r):
                HStack(spacing: 0) {
                    SpeedValue(title: L("Download"), value: String(format: "%.0f", r.down), unit: "Mbps", color: Theme.download)
                    SpeedValue(title: L("Upload"), value: String(format: "%.0f", r.up), unit: "Mbps", color: Theme.upload)
                    SpeedValue(title: L("Latência"), value: String(format: "%.0f", r.latency), unit: "ms", color: .orange)
                    IconButton(icon: "arrow.clockwise", help: L("Testar de novo")) { net.runSpeedTest() }
                }
                Text(r.quality).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: L("Dispositivos"), icon: "dot.radiowaves.left.and.right", color: .blue)
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
            CardHeader(title: L("Quem está usando a CPU"), icon: "list.bullet", color: .secondary) {
                Button(L("Monitor de Atividade")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.indigo)
            }
            if m.topProcesses.isEmpty {
                Text(L("Carregando…")).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(m.topProcesses.prefix(5)) { p in
                ProcessRow(p: p) { force in
                    if !m.quit(p, force: force) { NSSound.beep() }
                }
            }
        }
        .card()
    }

    private func batteryText(_ b: BatteryInfo) -> String {
        let t = b.minutesLeft.map { "\($0 / 60)h\(String(format: "%02d", $0 % 60))" }
        if b.charging { return t.map { L("cheia em %@", $0) } ?? L("carregando") }
        if b.onAC { return L("na tomada") }
        return t.map { L("restam %@", $0) } ?? L("na bateria")
    }

    private var thermalText: String {
        switch m.thermal {
        case .nominal: L("Normal")
        case .fair: L("Morno")
        case .serious: L("Quente")
        case .critical: L("Crítico")
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
        .help(L("Copiar"))
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

// MARK: Ajustes

struct SettingsView: View {
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var updater: UpdaterModel
    @AppStorage(MenuBarItem.key) private var menuBarItems = "cpu,ram"
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("language") private var language = "auto"
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("maxItems") private var maxItems = 300
    @AppStorage("autoDeleteDays") private var autoDeleteDays = 0
    @AppStorage("ignoreConcealed") private var ignoreConcealed = true
    @AppStorage("paused") private var paused = false
    @AppStorage("ignoredApps") private var ignoredApps = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section(L("Aparência")) {
                Picker(L("Tema"), selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Picker(L("Idioma"), selection: $language) {
                    Text(L("Automático (sistema)")).tag("auto")
                    Divider()
                    ForEach(Lang.allCases, id: \.rawValue) { Text($0.pickerName).tag($0.rawValue) }
                }
            }
            Section(L("Barra de menus")) {
                MenuBarItemsPicker(selection: $menuBarItems)
                Toggle(L("Abrir ao iniciar o Mac"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }
            AlertsSection()
            Section(L("Permissões")) {
                HStack {
                    Label(L("Acessibilidade"), systemImage: axTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(axTrusted ? .green : .orange)
                    Spacer()
                    if !axTrusted {
                        Button(L("Permitir")) {
                            ClipboardManager.requestAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { axTrusted = AXIsProcessTrusted() }
                        }
                    }
                }
                Text(L("Usada para colar automaticamente e para travar o teclado na limpeza."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Clipboard")) {
                Toggle(L("Colar automaticamente ao escolher"), isOn: $autoPaste)
                Toggle(L("Pausar captura"), isOn: $paused)
                Toggle(L("Ignorar senhas (1Password, Keychain…)"), isOn: $ignoreConcealed)
                Stepper(L("Guardar %d itens", maxItems), value: $maxItems, in: 50...2000, step: 50)
                Picker(L("Apagar itens com mais de"), selection: $autoDeleteDays) {
                    Text(L("Nunca")).tag(0)
                    ForEach([1, 7, 30, 90], id: \.self) { d in
                        Text(d == 1 ? L("1 dia") : L("%d dias", d)).tag(d)
                    }
                }
                .onChange(of: autoDeleteDays) { _, _ in clipboard.pruneAndSaveIfNeeded() }
                TextField(L("Ignorar apps"), text: $ignoredApps, prompt: Text(L("bundle IDs separados por vírgula")))
                Button(L("Limpar histórico (mantém fixados)"), role: .destructive) { confirmClear = true }
                    .confirmationDialog(L("Apagar todo o histórico não fixado?"), isPresented: $confirmClear) {
                        Button(L("Apagar"), role: .destructive) { clipboard.clear() }
                    }
            }
            Section(L("Atalhos")) {
                LabeledContent(L("Histórico do clipboard")) {
                    ShortcutRecorder(name: HotKeyCenter.clipboardKey, fallback: .clipboardDefault)
                }
                LabeledContent(L("Abrir este menu")) {
                    ShortcutRecorder(name: HotKeyCenter.menuKey, fallback: .menuDefault)
                }
            }
            Section(L("Ajuda")) {
                HStack(spacing: 8) {
                    Button { Feedback.reportBug() } label: { Label(L("Reportar um problema…"), systemImage: "ladybug") }
                    Button { Feedback.suggestIdea() } label: { Label(L("Sugerir uma ideia…"), systemImage: "lightbulb") }
                    Spacer()
                    Button { Feedback.openRepo() } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(.borderless).help(L("Ver no GitHub"))
                }
                Text(L("Abre o GitHub com a versão do app e do macOS já preenchidas. Você revisa antes de enviar."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Atualizações")) {
                Toggle(L("Procurar atualizações automaticamente"), isOn: $updater.automaticallyChecks)
                HStack {
                    Text("Menew \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Procurar agora")) { updater.checkForUpdates() }
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button(L("Sair do Menew")) { NSApp.terminate(nil) }
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
        case .system: L("Automático")
        case .light: L("Claro")
        case .dark: L("Escuro")
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

/// O que aparece ao lado do ícone na barra de menus, na ordem abaixo
enum MenuBarItem: String, CaseIterable {
    case cpu, cpuGraph, ram, net, disk, battery

    static let key = "menuBarItems"

    static var selected: [MenuBarItem] {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        let set = Set(raw.split(separator: ",").map(String.init))
        return allCases.filter { set.contains($0.rawValue) }
    }

    /// Converte a opção antiga ("CPU + RAM" etc.) na primeira vez
    static var migratedDefault: String {
        switch UserDefaults.standard.string(forKey: "menuBarStyle") {
        case "icon": ""
        case "cpu": "cpu"
        case "network": "net"
        case "all": "cpu,ram,net"
        default: "cpu,ram"
        }
    }

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .cpuGraph: L("Gráfico da CPU")
        case .ram: L("Memória")
        case .net: L("Rede")
        case .disk: L("Disco")
        case .battery: L("Bateria")
        }
    }

    var icon: String {
        switch self {
        case .cpu: "cpu"
        case .cpuGraph: "chart.bar.fill"
        case .ram: "memorychip"
        case .net: "arrow.up.arrow.down"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        }
    }

    @MainActor func segment(_ m: SystemMonitor) -> StatusSegment? {
        switch self {
        case .cpu: .stat("CPU", Fmt.pct(m.cpu))
        case .cpuGraph: .graph(Array(m.cpuHistory.suffix(12)))
        case .ram: .stat("RAM", Fmt.pct(m.memFraction))
        case .net: .net(Fmt.shortRate(m.netIn), Fmt.shortRate(m.netOut))
        case .disk: .stat("SSD", Fmt.pct(m.diskFraction))
        case .battery: m.battery.map { .stat("BAT", "\($0.percent)%") }
        }
    }

    /// Valores fixos para a prévia nos Ajustes e nas capturas
    var sample: StatusSegment {
        switch self {
        case .cpu: .stat("CPU", "23%")
        case .cpuGraph: .graph([0.2, 0.35, 0.3, 0.6, 0.45, 0.8, 0.5, 0.3, 0.4, 0.25, 0.55, 0.35])
        case .ram: .stat("RAM", "64%")
        case .net: .net("1.2M", "48K")
        case .disk: .stat("SSD", "58%")
        case .battery: .stat("BAT", "80%")
        }
    }
}
