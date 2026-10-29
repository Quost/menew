import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
import ApplicationServices

enum Tab: String, CaseIterable {
    case system = "Sistema", clipboard = "Clipboard", actions = "Ações", notes = "Notas", settings = "Ajustes"
    case cleaner = "Liberar espaço"
    /// Abas na barra, sem os módulos desligados
    static var visible: [Tab] { [.system] + Module.allCases.filter(\.isOn).map(\.tab) }
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

    @AppStorage("language") private var language = "auto"
    // Redesenha as abas quando um módulo liga ou desliga
    @AppStorage(Module.clipboard.key) private var clipboardOn = true
    @AppStorage(Module.actions.key) private var actionsOn = true
    @AppStorage(Module.notes.key) private var notesOn = true

    var body: some View {
        VStack(spacing: 0) {
            // O vidro dos cards não respeita o recorte da rolagem: o cabeçalho fica por cima e o conteúdo é recortado
            VStack(spacing: 0) {
                header
                if let v = updater.pendingVersion { updateBanner(v) }
                if !isSubpage { tabBar }
            }
            .zIndex(1)

            Group {
                switch nav.tab {
                case .system: SystemView(m: monitor, net: internet)
                case .clipboard: ClipboardTabView(manager: clipboard, state: clipState, onActivate: onPickClip)
                case .actions: ActionsView(tb: toolbox, clipboard: clipboard) { nav.tab = .cleaner }
                case .cleaner: CleanerView(cleaner: cleaner, monitor: monitor)
                case .notes: NotesView(store: notes)
                case .settings: SettingsView(clipboard: clipboard, monitor: monitor, updater: updater)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
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
        .onChange(of: [clipboardOn, actionsOn, notesOn]) { _, _ in
            // Desligou o módulo da aba aberta: volta para o Sistema
            if let m = Module.allCases.first(where: { $0.tab == nav.tab }), !m.isOn { nav.tab = .system }
            // Os atalhos de janelas fazem parte das Ações
            WindowManager.shared.registerHotKeys()
        }
    }

    /// Aviso discreto de versão nova: a janela do Sparkle só abre quando você clica
    private func updateBanner(_ version: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.indigo)
            Text(L("Menew %@ está disponível", version)).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer()
            PillButton(title: L("Ver novidades"), primary: true) { updater.checkForUpdates() }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass()
        .padding(.horizontal, 14).padding(.bottom, 10)
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
        GlassSegmented(selection: $nav.tab, options: Tab.visible.map { .init(value: $0, title: L($0.rawValue), icon: $0.icon) })
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
                diskCard
                if !net.devices.isEmpty { devicesCard }
                processesCard
                HStack(spacing: 10) {
                    MiniStat(icon: "clock.fill", color: .indigo, title: L("Ligado há"), value: Fmt.duration(m.uptime))
                    MiniStat(icon: "thermometer.medium", color: thermalColor, title: L("Temperatura"), value: thermalText)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .noLiquidGlass()
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
            if let g = m.gpu {
                HStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("GPU").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Text(Fmt.pct(g)).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .frame(width: 72, alignment: .leading)
                    Sparkline(values: m.gpuHistory, color: Theme.load(g, base: .pink))
                        .frame(height: 22)
                }
            }
        }
        .card()
    }

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: L("Disco"), icon: "internaldrive", color: Theme.disk) {
                Text(L("%@ livres", Fmt.bytes(m.diskFree))).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                NetStat(title: L("Leitura"), icon: "arrow.down.doc", color: Theme.disk, value: m.diskRead, history: m.diskReadHistory)
                NetStat(title: L("Gravação"), icon: "square.and.arrow.down", color: .orange, value: m.diskWrite, history: m.diskWriteHistory)
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
    let monitor: SystemMonitor
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
    @AppStorage(Module.clipboard.key) private var clipboardOn = true
    @AppStorage(Module.actions.key) private var actionsOn = true
    @AppStorage(WindowManager.shortcutsKey) private var windowShortcuts = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassSection(title: L("Aparência")) {
                    SettingRow(title: L("Tema")) {
                        GlassSegmented(selection: $appearance, options: AppAppearance.allCases.map {
                            .init(value: $0.rawValue, title: $0.label, icon: $0.icon)
                        }, expand: false)
                    }
                    RowDivider()
                    SettingRow(title: L("Idioma")) {
                        GlassMenu(selection: $language, options: [("auto", L("Automático (sistema)"))]
                                  + Lang.allCases.map { ($0.rawValue, $0.pickerName) })
                    }
                }

                GlassSection(title: L("Módulos"), footer: L("O Sistema fica sempre ligado.")) {
                    ForEach(Array(Module.allCases.enumerated()), id: \.element) { i, m in
                        if i > 0 { RowDivider(inset: 52) }
                        ModuleToggle(m)
                    }
                }

                GlassSection(title: L("Barra de menus")) {
                    MenuBarItemsPicker(selection: $menuBarItems, monitor: monitor)
                    RowDivider()
                    ToggleRow(title: L("Abrir ao iniciar o Mac"), isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in
                            do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                            catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                        }
                }

                AlertsSection()

                GlassSection(title: L("Permissões"), footer: L("Usada para colar automaticamente e para travar o teclado na limpeza.")) {
                    SettingRow(title: L("Acessibilidade"), icon: axTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill") {
                        if axTrusted {
                            Text(L("Permitido")).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.green)
                        } else {
                            PillButton(title: L("Permitir"), primary: true) {
                                ClipboardManager.requestAccessibility()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { axTrusted = AXIsProcessTrusted() }
                            }
                        }
                    }
                }

                if clipboardOn {
                GlassSection(title: L("Clipboard")) {
                    ToggleRow(title: L("Colar automaticamente ao escolher"), isOn: $autoPaste)
                    RowDivider()
                    ToggleRow(title: L("Pausar captura"), isOn: $paused)
                    RowDivider()
                    ToggleRow(title: L("Ignorar senhas (1Password, Keychain…)"), isOn: $ignoreConcealed)
                    RowDivider()
                    SettingRow(title: L("Guardar %d itens", maxItems)) {
                        GlassStepper(value: $maxItems, range: 50...2000, step: 50)
                    }
                    RowDivider()
                    SettingRow(title: L("Apagar itens com mais de")) {
                        GlassMenu(selection: $autoDeleteDays, options: [(0, L("Nunca"))]
                                  + [1, 7, 30, 90].map { ($0, $0 == 1 ? L("1 dia") : L("%d dias", $0)) })
                    }
                    .onChange(of: autoDeleteDays) { _, _ in clipboard.pruneAndSaveIfNeeded() }
                    RowDivider()
                    IgnoredAppsRow(raw: $ignoredApps)
                    RowDivider()
                    SettingRow(title: L("Limpar histórico (mantém fixados)")) {
                        PillButton(title: L("Limpar"), icon: "trash") { confirmClear = true }
                    }
                    .confirmationDialog(L("Apagar todo o histórico não fixado?"), isPresented: $confirmClear) {
                        Button(L("Apagar"), role: .destructive) { clipboard.clear() }
                    }
                }
                }

                GlassSection(title: L("Atalhos")) {
                    if clipboardOn {
                        SettingRow(title: L("Histórico do clipboard")) {
                            ShortcutRecorder(name: HotKeyCenter.clipboardKey, fallback: .clipboardDefault)
                        }
                        RowDivider()
                    }
                    SettingRow(title: L("Abrir este menu")) {
                        ShortcutRecorder(name: HotKeyCenter.menuKey, fallback: .menuDefault)
                    }
                    if actionsOn {
                        RowDivider()
                        SettingRow(title: L("Mutar microfone")) {
                            ShortcutRecorder(name: HotKeyCenter.micKey, fallback: .micDefault)
                        }
                        RowDivider()
                        ToggleRow(title: L("Organizar janelas com ⌃⌥"),
                                  detail: L("⌃⌥ + setas para metades, U I J K para cantos, ↩ para maximizar. Desligue se usa outro app para isso."),
                                  isOn: $windowShortcuts)
                            .onChange(of: windowShortcuts) { _, _ in WindowManager.shared.registerHotKeys() }
                    }
                }

                GlassSection(title: L("Ajuda"),
                             footer: L("Abre o GitHub com a versão do app e do macOS já preenchidas. Você revisa antes de enviar.")) {
                    LinkRow(title: L("Reportar um problema…"), icon: "ladybug") { Feedback.reportBug() }
                    RowDivider()
                    LinkRow(title: L("Sugerir uma ideia…"), icon: "lightbulb") { Feedback.suggestIdea() }
                    RowDivider()
                    LinkRow(title: L("Ver no GitHub"), icon: "chevron.left.forwardslash.chevron.right") { Feedback.openRepo() }
                    RowDivider()
                    LinkRow(title: L("Ver a apresentação de novo"), icon: "sparkles") {
                        NotificationCenter.default.post(name: .showWelcome, object: nil)
                    }
                }

                GlassSection(title: L("Atualizações")) {
                    ToggleRow(title: L("Procurar atualizações automaticamente"), isOn: $updater.automaticallyChecks)
                    RowDivider()
                    SettingRow(title: "Menew \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")") {
                        PillButton(title: L("Procurar agora"), icon: "arrow.down.circle") { updater.checkForUpdates() }
                    }
                }

                HStack {
                    Spacer()
                    PillButton(title: L("Sair do Menew"), icon: "power") { NSApp.terminate(nil) }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .noLiquidGlass()
        .scrollIndicators(.never)
        .onAppear { axTrusted = AXIsProcessTrusted() }
    }
}

/// Apps cujo conteúdo copiado não entra no histórico: escolha da lista de apps abertos ou do Finder
struct IgnoredAppsRow: View {
    @Binding var raw: String

    private var ids: [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Ignorar apps")).font(.system(size: 12.5))
                    Text(L("O que você copiar neles não vai para o histórico."))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    let running = runningApps
                    if !running.isEmpty {
                        Section(L("Abertos agora")) {
                            ForEach(running, id: \.bundleIdentifier) { app in
                                Button {
                                    if let id = app.bundleIdentifier { add(id) }
                                } label: {
                                    Label {
                                        Text(app.localizedName ?? app.bundleIdentifier ?? "")
                                    } icon: {
                                        if let icon = app.icon { Image(nsImage: Self.small(icon)) }
                                    }
                                }
                            }
                        }
                        Divider()
                    }
                    Button(L("Escolher outro app…")) { chooseApp() }
                } label: {
                    Label(L("Adicionar"), systemImage: "plus")
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .contentShape(Capsule())
                        .glass(in: Capsule(), interactive: true)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            if !ids.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(ids, id: \.self) { id in
                        HStack(spacing: 5) {
                            if let icon = AppIcons.icon(for: id) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            }
                            Text(Self.name(for: id)).font(.system(size: 11.5)).lineLimit(1)
                            Button { remove(id) } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain).help(L("Remover"))
                        }
                        .padding(.leading, 6).padding(.trailing, 7).padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                        .help(id)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// Apps com janela abertos agora, sem os que já estão na lista e sem o próprio Menew
    private var runningApps: [NSRunningApplication] {
        let current = Set(ids)
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, !current.contains(id) else { return false }
                return seen.insert(id).inserted
            }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func add(_ id: String) {
        guard !ids.contains(id) else { return }
        raw = (ids + [id]).joined(separator: ",")
    }

    private func remove(_ id: String) {
        raw = ids.filter { $0 != id }.joined(separator: ",")
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = L("Escolher outro app…")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        // Grava direto nos ajustes: o popover pode fechar enquanto o painel está aberto
        panel.begin { response in
            guard response == .OK else { return }
            let picked = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            let current = (UserDefaults.standard.string(forKey: "ignoredApps") ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let merged = current + picked.filter { !current.contains($0) }
            UserDefaults.standard.set(merged.joined(separator: ","), forKey: "ignoredApps")
        }
    }

    static func name(for id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func small(_ icon: NSImage) -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16))
        img.lockFocus()
        icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        img.unlockFocus()
        return img
    }
}

/// Distribui as fichas em linhas, quebrando quando não cabem
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
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
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
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

    /// Valores fixos para as capturas da barra de menus
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
