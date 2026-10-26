import SwiftUI
import ServiceManagement
import ApplicationServices

enum Tab: String, CaseIterable {
    case system = "Sistema", clipboard = "Clipboard", actions = "Ações", settings = "Ajustes"
    var icon: String {
        switch self {
        case .system: "gauge.with.dots.needle.67percent"
        case .clipboard: "doc.on.clipboard"
        case .actions: "bolt.fill"
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
    let clipState: ClipListState
    var onPickClip: (ClipItem, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button { nav.tab = t } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon).font(.system(size: 14))
                            Text(t.rawValue).font(.caption2)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(nav.tab == t ? Color.accentColor.opacity(0.18) : .clear))
                        .foregroundStyle(nav.tab == t ? Color.accentColor : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()

            Group {
                switch nav.tab {
                case .system: SystemView(m: monitor)
                case .clipboard: ClipboardListView(manager: clipboard, state: clipState, compact: true, onActivate: onPickClip)
                case .actions: ActionsView(tb: toolbox, clipboard: clipboard)
                case .settings: SettingsView(clipboard: clipboard)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let t = toolbox.toast {
                Text(t).font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 380, height: 540)
        .animation(.easeOut(duration: 0.15), value: toolbox.toast)
    }
}

// MARK: Sistema

struct SystemView: View {
    @ObservedObject var m: SystemMonitor

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Card(title: "CPU", icon: "cpu", value: Fmt.pct(m.cpu), tint: tint(m.cpu)) {
                    Sparkline(values: m.cpuHistory, color: tint(m.cpu)).frame(height: 36)
                }
                Card(title: "Memória", icon: "memorychip", value: Fmt.pct(m.memFraction), tint: tint(m.memFraction)) {
                    UsageBar(fraction: m.memFraction, tint: tint(m.memFraction))
                    Text("\(Fmt.mem(m.memUsed)) usados de \(Fmt.mem(m.memTotal))").caption()
                }
                Card(title: "Disco", icon: "internaldrive", value: Fmt.pct(m.diskFraction), tint: tint(m.diskFraction)) {
                    UsageBar(fraction: m.diskFraction, tint: tint(m.diskFraction))
                    Text("\(Fmt.bytes(m.diskFree)) livres de \(Fmt.bytes(m.diskTotal))").caption()
                }
                if let b = m.battery {
                    Card(title: "Bateria", icon: batteryIcon(b), value: "\(b.percent)%",
                         tint: b.percent < 20 && !b.onAC ? .red : .green) {
                        UsageBar(fraction: Double(b.percent) / 100, tint: b.percent < 20 && !b.onAC ? .red : .green)
                        Text(batteryText(b)).caption()
                    }
                }
                Card(title: "Rede", icon: "network", value: m.localIP, tint: .blue) {
                    HStack {
                        Label(Fmt.rate(m.netIn), systemImage: "arrow.down").foregroundStyle(.blue)
                        Spacer()
                        Label(Fmt.rate(m.netOut), systemImage: "arrow.up").foregroundStyle(.purple)
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
                HStack(spacing: 10) {
                    MiniStat(icon: "clock", title: "Ligado há", value: Fmt.duration(m.uptime))
                    MiniStat(icon: "thermometer.medium", title: "Temperatura", value: thermalText(m.thermal))
                }
                Card(title: "Processos que mais usam CPU", icon: "list.number", value: "", tint: .secondary) {
                    if m.topProcesses.isEmpty {
                        Text("Carregando…").caption()
                    }
                    ForEach(m.topProcesses) { p in
                        HStack {
                            Text(p.name).lineLimit(1)
                            Spacer()
                            Text(Fmt.mem(p.memKB * 1024)).foregroundStyle(.secondary)
                            Text(String(format: "%.1f%%", p.cpu)).frame(width: 52, alignment: .trailing)
                        }
                        .font(.system(size: 11.5))
                    }
                    Button("Abrir Monitor de Atividade") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                    .buttonStyle(.link).font(.caption)
                }
            }
            .padding(12)
        }
        .onAppear { m.wantsProcesses = true; m.refreshProcesses() }
        .onDisappear { m.wantsProcesses = false }
    }

    private func tint(_ f: Double) -> Color { f > 0.85 ? .red : f > 0.65 ? .orange : .green }

    private func batteryIcon(_ b: BatteryInfo) -> String {
        if b.charging { return "battery.100.bolt" }
        switch b.percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryText(_ b: BatteryInfo) -> String {
        let time = b.minutesLeft.map { " · \($0 / 60)h\(String(format: "%02d", $0 % 60))" } ?? ""
        if b.charging { return "Carregando" + time.replacingOccurrences(of: " · ", with: " · cheia em ") }
        if b.onAC { return "Na tomada" }
        return "Na bateria" + time.replacingOccurrences(of: " · ", with: " · restam ")
    }

    private func thermalText(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: "Normal"
        case .fair: "Morno"
        case .serious: "Quente"
        case .critical: "Crítico"
        @unknown default: "—"
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    let icon: String
    let value: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(tint)
            }
            content
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quinary))
    }
}

struct MiniStat: View {
    let icon: String, title: String, value: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).caption()
                Text(value).font(.system(size: 12, weight: .semibold))
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quinary))
    }
}

struct UsageBar: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint.gradient).frame(width: max(4, g.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 7)
        .animation(.easeOut, value: fraction)
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { g in
            let step = g.size.width / CGFloat(max(values.count - 1, 1))
            let pts = values.enumerated().map { CGPoint(x: CGFloat($0) * step, y: g.size.height * (1 - CGFloat($1))) }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: g.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

extension Text {
    func caption() -> some View { self.font(.caption).foregroundStyle(.secondary) }
}

// MARK: Ações

struct ActionsView: View {
    @ObservedObject var tb: Toolbox
    let clipboard: ClipboardManager
    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Energia")
                LazyVGrid(columns: cols, spacing: 8) {
                    ActionTile(icon: "cup.and.saucer.fill", title: "Manter acordado", on: tb.keepAwake) {
                        tb.setKeepAwake(!tb.keepAwake)
                    }
                    ActionTile(icon: "timer", title: "Acordado 1h", on: false) {
                        tb.setKeepAwake(true, minutes: 60); tb.show("Acordado por 1 hora")
                    }
                    ActionTile(icon: "lock.fill", title: "Bloquear tela", on: false) { tb.lockScreen() }
                }
                section("Finder")
                LazyVGrid(columns: cols, spacing: 8) {
                    ActionTile(icon: "eye", title: "Arquivos ocultos", on: tb.hiddenFiles) { tb.toggleHiddenFiles() }
                    ActionTile(icon: "menubar.dock.rectangle", title: "Ocultar mesa", on: tb.desktopIconsHidden) { tb.toggleDesktopIcons() }
                    ActionTile(icon: "eject.fill", title: "Ejetar discos", on: false) { tb.ejectAll() }
                    ActionTile(icon: "trash", title: "Esvaziar lixeira", on: false) { tb.emptyTrash() }
                    ActionTile(icon: "arrow.down.circle", title: "Downloads", on: false) {
                        tb.open(NSHomeDirectory() + "/Downloads")
                    }
                }
                section("Ferramentas")
                LazyVGrid(columns: cols, spacing: 8) {
                    ActionTile(icon: "circle.lefthalf.filled", title: "Modo escuro", on: false) { tb.toggleDarkMode() }
                    ActionTile(icon: "camera.viewfinder", title: "Print → clipboard", on: false) { tb.screenshotToClipboard() }
                    ActionTile(icon: "eyedropper", title: "Conta-gotas", on: false) { tb.pickColor(clipboard: clipboard) }
                    ActionTile(icon: "textformat", title: "Limpar formatação", on: false) { tb.plainTextClipboard() }
                    ActionTile(icon: "chart.bar.xaxis", title: "Monitor de Atividade", on: false) {
                        tb.open("/System/Applications/Utilities/Activity Monitor.app")
                    }
                    ActionTile(icon: "terminal", title: "Terminal", on: false) {
                        tb.open("/System/Applications/Utilities/Terminal.app")
                    }
                }
            }
            .padding(12)
        }
    }

    private func section(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}

struct ActionTile: View {
    let icon: String
    let title: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 18))
                    .foregroundStyle(on ? Color.white : Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(on ? Color.accentColor : Color.accentColor.opacity(0.12)))
                Text(title).font(.system(size: 10.5)).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 10).fill(hover ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Ajustes

struct SettingsView: View {
    @ObservedObject var clipboard: ClipboardManager
    @AppStorage("menuBarStyle") private var style = MenuBarStyle.cpuRam.rawValue
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
            Section("Clipboard") {
                Toggle("Colar automaticamente ao escolher", isOn: $autoPaste)
                if autoPaste && !axTrusted {
                    HStack {
                        Text("Precisa de Acessibilidade").foregroundStyle(.orange)
                        Spacer()
                        Button("Permitir") {
                            ClipboardManager.requestAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { axTrusted = AXIsProcessTrusted() }
                        }
                    }
                    .font(.caption)
                }
                Toggle("Pausar captura", isOn: $paused)
                Toggle("Ignorar senhas (1Password, Keychain…)", isOn: $ignoreConcealed)
                Stepper("Guardar \(maxItems) itens", value: $maxItems, in: 50...2000, step: 50)
                TextField("Ignorar apps (bundle IDs, vírgula)", text: $ignoredApps)
                    .font(.caption)
                Button("Limpar histórico (mantém fixados)", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Apagar todo o histórico não fixado?", isPresented: $confirmClear) {
                        Button("Apagar", role: .destructive) { clipboard.clear() }
                    }
            }
            Section("Atalhos") {
                LabeledContent("Histórico do clipboard", value: "⌘⇧V")
                LabeledContent("Abrir este menu", value: "⌥⌘M")
            }
            Section {
                HStack {
                    Text("MeuMenu 1.0").foregroundStyle(.secondary)
                    Spacer()
                    Button("Sair") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { axTrusted = AXIsProcessTrusted() }
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
