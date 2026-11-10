import AppKit
import SwiftUI

/// Janela Menew: a profundidade. A barra de menus mostra o "agora"; aqui ficam a memória, o histórico,
/// o desempenho em detalhe, as ferramentas e o resto, numa barra lateral como a dos Ajustes do Sistema.
enum HubSection: String, CaseIterable, Identifiable {
    case overview, memory, recordings, agents, clipboard, notes, performance, history, battery, tools, automations, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: L("Visão geral")
        case .memory: L("Memória")
        case .recordings: L("Gravações")
        case .agents: L("Agentes de IA")
        case .clipboard: L("Clipboard")
        case .notes: L("Notas")
        case .performance: L("Desempenho")
        case .history: L("Histórico e tempo de tela")
        case .battery: L("Bateria")
        case .tools: L("Ferramentas")
        case .automations: L("Apps, perfis e automações")
        case .settings: L("Ajustes")
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .memory: "brain.head.profile"
        case .recordings: "waveform"
        case .agents: "sparkles"
        case .clipboard: "doc.on.clipboard.fill"
        case .notes: "note.text"
        case .performance: "gauge.with.dots.needle.67percent"
        case .history: "chart.xyaxis.line"
        case .battery: "battery.75percent"
        case .tools: "wrench.and.screwdriver.fill"
        case .automations: "gearshape.2.fill"
        case .settings: "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .overview: Theme.indigo
        case .memory: .pink
        case .recordings: .red
        case .agents: .orange
        case .clipboard: .purple
        case .notes: .yellow
        case .performance: .blue
        case .history: .indigo
        case .battery: .green
        case .tools: .teal
        case .automations: .gray
        case .settings: .gray
        }
    }

    /// Seções que somem quando o módulo está desligado ou o Mac não tem bateria
    @MainActor var isVisible: Bool {
        switch self {
        case .clipboard: Module.clipboard.isOn
        case .notes: Module.notes.isOn
        case .battery: SystemMonitorInfo.hasBattery
        default: true
        }
    }
}

@MainActor
final class MenewWindow: NSObject, NSWindowDelegate {
    static let shared = MenewWindow()
    private var window: NSWindow?
    let state = HubState()

    func show(_ section: HubSection? = nil, category: SettingsCategory? = nil) {
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        guard let app = NSApp.delegate as? AppDelegate else { return }
        if let section { state.section = section }
        if let category { state.section = .settings; state.category = category }
        let w = window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Menew"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 780, height: 500)
            w.delegate = self
            w.contentView = NSHostingView(rootView: HubView(state: state, monitor: app.monitor, clipboard: app.clipboard, notes: app.notes,
                                                             internet: app.internet, toolbox: app.toolbox, updater: app.updater))
            if !w.setFrameUsingName("MenewHub") { w.center() }
            w.setFrameAutosaveName("MenewHub")
            return w
        }()
        window = w
        app.monitor.isVisible = true
        app.monitor.wantsProcesses = true
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let app = NSApp.delegate as? AppDelegate, !app.isMenuOpen else { return }
        app.monitor.isVisible = false
        app.monitor.wantsProcesses = false
    }
}

@MainActor
final class HubState: ObservableObject {
    @Published var section: HubSection = .overview
    /// A categoria aberta quando a seção é Ajustes
    @Published var category: SettingsCategory = .general
    @Published var query = ""
}

struct HubView: View {
    @ObservedObject var state: HubState
    let monitor: SystemMonitor
    let clipboard: ClipboardManager
    let notes: NotesStore
    let internet: InternetInfo
    let toolbox: Toolbox
    @ObservedObject var updater: UpdaterModel
    @AppStorage(Module.clipboard.key) private var clipboardOn = true
    @AppStorage(Module.notes.key) private var notesOn = true
    @StateObject private var clipState = ClipListState()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(state.section == .settings ? state.category.title : state.section.title).font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 10)
                content
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id(state.section == .settings ? "settings." + state.category.rawValue : state.section.rawValue)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.windowFill)
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Uma busca só: acha seções e ajustes
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField(L("Buscar"), text: $state.query).textFieldStyle(.plain).font(.system(size: 13))
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !state.query.isEmpty {
                        searchResults
                    } else if state.section == .settings {
                        // Dentro dos Ajustes: as categorias, com um caminho de volta
                        row(icon: "chevron.left", color: .clear, title: "Menew", on: false, plainIcon: true) { state.section = .overview }
                        ForEach(SettingsCategory.allCases) { c in
                            row(icon: c.icon, color: c.color, title: c.title, on: state.category == c) { state.category = c }
                        }
                    } else {
                        ForEach(HubSection.allCases.filter { $0.isVisible && $0 != .settings }) { s in
                            if s == .performance {
                                Text(L("Mac")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase)
                                    .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 2)
                            }
                            row(icon: s.icon, color: s.color, title: s.title, on: state.section == s) { state.section = s }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            if state.section != .settings && state.query.isEmpty {
                row(icon: "gearshape.fill", color: .gray, title: L("Ajustes"), on: false) { state.section = .settings }
            }
        }
        .padding(.horizontal, 10).padding(.top, 38).padding(.bottom, 12)
        .frame(width: 230)
        .background(VisualEffect(material: .sidebar).ignoresSafeArea())
    }

    @ViewBuilder private var searchResults: some View {
        let q = PaletteSearch.fold(state.query.trimmingCharacters(in: .whitespaces))
        let sections = HubSection.allCases.filter { $0.isVisible && $0 != .settings && PaletteSearch.fold($0.title).contains(q) }
        let cats = SettingsCategory.allCases.filter { PaletteSearch.fold($0.keywords).contains(q) }
        ForEach(sections) { s in
            row(icon: s.icon, color: s.color, title: s.title, on: false) { state.section = s; state.query = "" }
        }
        if !cats.isEmpty {
            Text(L("Ajustes")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
            ForEach(cats) { c in
                row(icon: c.icon, color: c.color, title: c.title, on: false) { state.section = .settings; state.category = c; state.query = "" }
            }
        }
        if sections.isEmpty && cats.isEmpty {
            Text(L("Nada encontrado")).font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 6)
        }
    }

    private func row(icon: String, color: Color, title: String, on: Bool, plainIcon: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if plainIcon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 22, height: 22)
                } else {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
                }
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch state.section {
        case .overview:
            HubOverview(m: monitor, open: { state.section = $0 })
        case .memory:
            MemoryView(store: .shared)
        case .recordings:
            RecordingsView()
        case .agents:
            AgentsView().frame(maxWidth: 760)
        case .clipboard:
            ClipboardTabView(manager: clipboard, state: clipState) { item, _ in
                clipboard.copy(item)
                HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
            }
            .frame(maxWidth: 720)
        case .notes:
            NotesView(store: notes, nav: nil).frame(maxWidth: 720)
        case .performance:
            SystemView(m: monitor, net: internet).frame(maxWidth: 560)
        case .history:
            ScrollView {
                VStack(spacing: 12) {
                    SystemHistoryCard()
                    ScreenTimeCard()
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .frame(maxWidth: 640)
        case .battery:
            ScrollView {
                VStack(spacing: 12) {
                    if let b = monitor.battery, let h = monitor.batteryHealth { BatteryCard(battery: b, health: h) }
                    BatteryWearCard()
                    HistoryMini(metric: .energy)
                    AccessoriesCard()
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .frame(maxWidth: 560)
        case .tools:
            HubTools(monitor: monitor)
        case .settings:
            SettingsView(clipboard: clipboard, monitor: monitor, updater: updater, category: state.category)
                .padding(.horizontal, 10)
                .frame(maxWidth: 640, alignment: .topLeading)
        case .automations:
            ActionsView(tb: toolbox, clipboard: clipboard, group: .system, showsBack: false) { state.section = .tools }
                .frame(maxWidth: 560)
        }
    }
}

/// Visão geral: o dia, a saúde do Mac, o tempo de tela e o que você guardou
struct HubOverview: View {
    @ObservedObject var m: SystemMonitor
    @ObservedObject var meetings = MeetingStore.shared
    @ObservedObject var memory = MemoryStore.shared
    @ObservedObject var screenTime = ScreenTime.shared
    var open: (HubSection) -> Void

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let today = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale))
                Text(today.prefix(1).uppercased() + today.dropFirst())
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                LazyVGrid(columns: cols, alignment: .leading, spacing: 14) {
                    card(L("Agenda de hoje"), action: nil) {
                        let rest = meetings.today.filter { $0.end > Date() }
                        if !meetings.isOn {
                            Text(L("Ligue o calendário em Ajustes › Calendário e relógios.")).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        } else if rest.isEmpty {
                            Text(L("Sem mais reuniões hoje")).font(.system(size: 13)).foregroundStyle(.secondary)
                        } else {
                            ForEach(rest.prefix(4), id: \.id) { mt in
                                HStack(spacing: 8) {
                                    Text(mt.start.formatted(date: .omitted, time: .shortened)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                                    Text(mt.title).font(.system(size: 12.5)).lineLimit(1)
                                }
                            }
                        }
                    }
                    card(L("Saúde do Mac"), action: { open(.performance) }) {
                        let issues = Self.problems(m)
                        Text(issues.isEmpty ? L("Tudo normal") : issues.joined(separator: ", "))
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(issues.isEmpty ? .green : .orange)
                        Text("CPU \(Fmt.pct(m.cpu)) · \(L("Memória")) \(Fmt.pct(m.memFraction)) · \(NowView.shortBytes(m.diskFree)) \(L("livres"))")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    card(L("Tempo de tela"), action: { open(.history) }) {
                        if screenTime.isOn {
                            let cats = screenTime.byCategory([ScreenTime.dayKey(Date())])
                            Text(ScreenTimeCard.format(cats.values.reduce(0, +))).font(.system(size: 18, weight: .bold))
                            Text(L("foco %@", ScreenTimeCard.format(cats[.focus] ?? 0))).font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            Text(L("Desligado")).font(.system(size: 14, weight: .semibold))
                            Button(L("Ligar")) { screenTime.setOn(true) }.buttonStyle(.plain).foregroundStyle(Color.accentColor).font(.system(size: 12.5, weight: .semibold))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("Guardado recentemente")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Abrir a memória")) { open(.memory) }.buttonStyle(.plain).foregroundStyle(Color.accentColor).font(.system(size: 12.5, weight: .semibold))
                    }
                    if memory.items.isEmpty {
                        Text(L("Aperte %@ para guardar o que está na tela. Depois é só buscar.", Shortcut.load(MemoryStore.shortcutKey, default: .memoryDefault).display))
                            .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                            ForEach(memory.items.prefix(4)) { item in
                                RecallCard(item: item, image: memory.image(for: item), on: false)
                                    .onTapGesture { open(.memory) }
                            }
                        }
                    }
                }
                .card(padding: 16)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
    }

    private func card<C: View>(_ title: String, action: (() -> Void)?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if action != nil { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary) }
            }
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .card(padding: 16)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }

    static func problems(_ m: SystemMonitor) -> [String] {
        var p: [String] = []
        if m.memPressure != .normal { p.append(L("memória no limite")) }
        if m.cpu > 0.85 { p.append(L("CPU alta")) }
        if m.diskTotal > 0, m.diskFree < 10_000_000_000 { p.append(L("pouco espaço")) }
        if m.thermal == .serious || m.thermal == .critical { p.append(L("Mac quente")) }
        if let b = m.battery, !b.onAC, b.percent <= 20 { p.append(L("bateria baixa")) }
        return p
    }
}

/// Ferramentas: o que antes eram botões soltos, cada um com uma linha do que faz
struct HubTools: View {
    let monitor: SystemMonitor
    private var app: AppDelegate? { NSApp.delegate as? AppDelegate }
    private let cols = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: cols, spacing: 12) {
                    tool("sparkles", .blue, L("Liberar espaço"), L("Caches, logs e arquivos grandes; você revisa antes")) {
                        app?.openCleanerFromHub()
                    }
                    tool("trash.square", .red, L("Desinstalar app"), L("O app e as sobras vão para a Lixeira")) { Uninstaller.show() }
                    tool("power.circle", .orange, L("Itens de login"), L("O que abre com o Mac ou roda escondido")) { StartupItems.show() }
                    tool("folder.badge.gearshape", .blue, L("Organizar arquivos"), L("Nomes e pastas pelo conteúdo; você revisa antes")) { OrganizerWindow.shared.show() }
                    tool("tray.full.fill", Theme.indigo, L("Estante"), L("Converter, reduzir e juntar imagens e PDFs")) { app?.shelf.show(nearMouse: false) }
                    tool("iphone.rear.camera", .green, L("Do iPhone"), L("Foto, scan ou desenho direto no Mac")) { ContinuityCamera.shared.showMenu(.clipboard) }
                    tool("captions.bubble.fill", .indigo, L("Legendas ao vivo"), L("Do som do Mac ou do microfone, com tradução")) { LiveCaptions.shared.toggle() }
                    tool("terminal", .gray, L("Scripts"), L("Cada script vira um comando da paleta")) { ScriptCommands.openFolder() }
                    tool("stethoscope", .pink, L("Por que meu Mac está lento?"), L("Diagnóstico explicado em palavras simples")) { DiagnosisWindow.shared.show(monitor) }
                    tool("doc.on.doc", .brown, L("Copiar relatório"), L("Modelo, macOS, memória e disco para o suporte")) { SystemReport.copy(monitor) }
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
    }

    private func tool(_ icon: String, _ color: Color, _ title: String, _ detail: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .card(padding: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
