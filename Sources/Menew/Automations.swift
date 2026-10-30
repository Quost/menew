import AppKit
import SwiftUI

// MARK: Modelo

/// "Quando X acontecer, faça Y". Gatilhos e ações do próprio Menew, mais os Atalhos que você já tem no app Atalhos.
struct Automation: Codable, Equatable, Identifiable {
    enum Trigger: Codable, Equatable {
        case time(hour: Int, minute: Int, weekdays: Set<Int>)  // 1 = domingo … 7 = sábado
        case power(plugged: Bool)
        case batteryBelow(Int)
        case app(bundleID: String, name: String, opened: Bool)
        case display(connected: Bool)
        case meeting(minutesBefore: Int)
        case focus(started: Bool)
        case wake
        case presentation(started: Bool)
    }

    enum Action: Codable, Equatable, Hashable {
        case profile(UUID)
        case keepAwake(Bool)
        case mic(muted: Bool)
        case dark(Bool)
        case openApp(path: String)
        case brightness(Int)
        case clipboardPaused(Bool)
        case quitApps
        case shortcut(name: String)
        case presentation(Bool)
    }

    var id = UUID()
    var enabled = true
    var trigger: Trigger
    var actions: [Action] = []
    var notify = true
    var lastRun: Date?
    var lastResult: String?

    static let `default` = Automation(trigger: .time(hour: 9, minute: 0, weekdays: [2, 3, 4, 5, 6]))
}

extension Automation.Trigger {
    enum Kind: String, CaseIterable { case time, power, battery, app, display, meeting, focus, presentation, wake }

    var kind: Kind {
        switch self {
        case .time: .time
        case .power: .power
        case .batteryBelow: .battery
        case .app: .app
        case .display: .display
        case .meeting: .meeting
        case .focus: .focus
        case .wake: .wake
        case .presentation: .presentation
        }
    }

    static func make(_ kind: Kind) -> Self {
        switch kind {
        case .time: .time(hour: 9, minute: 0, weekdays: [2, 3, 4, 5, 6])
        case .power: .power(plugged: true)
        case .battery: .batteryBelow(20)
        case .app: .app(bundleID: "", name: "", opened: true)
        case .display: .display(connected: true)
        case .meeting: .meeting(minutesBefore: 1)
        case .focus: .focus(started: true)
        case .wake: .wake
        case .presentation: .presentation(started: true)
        }
    }

    static func kindTitle(_ k: Kind) -> String {
        switch k {
        case .time: L("Num horário")
        case .power: L("Carregador")
        case .battery: L("Bateria baixa")
        case .app: L("Um app abrir ou fechar")
        case .display: L("Monitor externo")
        case .meeting: L("Reunião começando")
        case .focus: L("Timer de foco")
        case .wake: L("O Mac acordar")
        case .presentation: L("Modo apresentação")
        }
    }

    /// Frase curta: "Às 09:00, dias úteis"
    var title: String {
        switch self {
        case .time(let h, let m, let days):
            let time = String(format: "%02d:%02d", h, m)
            return L("Às %@, %@", time, Self.daysText(days))
        case .power(let plugged): return plugged ? L("Ao conectar o carregador") : L("Ao desconectar o carregador")
        case .batteryBelow(let p): return L("Bateria abaixo de %d%%", p)
        case .app(_, let name, let opened):
            let n = name.isEmpty ? L("um app") : name
            return opened ? L("Ao abrir %@", n) : L("Ao fechar %@", n)
        case .display(let connected): return connected ? L("Ao conectar um monitor") : L("Ao desconectar o monitor")
        case .meeting(let m): return m == 0 ? L("Quando uma reunião começar") : L("%d min antes de uma reunião", m)
        case .focus(let started): return started ? L("Ao iniciar o foco") : L("Ao terminar o foco")
        case .wake: return L("Quando o Mac acordar")
        case .presentation(let started): return started ? L("Ao ligar o modo apresentação") : L("Ao desligar o modo apresentação")
        }
    }

    var icon: String {
        switch self {
        case .time: "clock.fill"
        case .power(let p): p ? "powerplug.fill" : "powerplug"
        case .batteryBelow: "battery.25percent"
        case .app: "app.badge.fill"
        case .display: "display"
        case .meeting: "video.fill"
        case .focus: "timer"
        case .wake: "sunrise.fill"
        case .presentation: "play.rectangle.fill"
        }
    }

    static func daysText(_ days: Set<Int>) -> String {
        if days.count == 7 { return L("todo dia") }
        if days == [2, 3, 4, 5, 6] { return L("dias úteis") }
        if days == [1, 7] { return L("fins de semana") }
        let names = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { names[$0 - 1] }.joined(separator: ", ")
    }
}

extension Automation.Action {
    @MainActor var title: String {
        switch self {
        case .profile(let id): L("Ativar o perfil %@", ProfileStore.shared.profile(id)?.name ?? "?")
        case .keepAwake(let on): on ? L("Manter acordado") : L("Desligar manter acordado")
        case .mic(let muted): muted ? L("Mutar microfone") : L("Ligar microfone")
        case .dark(let on): on ? L("Modo escuro") : L("Modo claro")
        case .openApp(let path): L("Abrir %@", FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""))
        case .brightness(let v): L("Brilho em %d%%", v)
        case .clipboardPaused(let on): on ? L("Pausar o clipboard") : L("Retomar captura do clipboard")
        case .quitApps: L("Fechar todos os apps")
        case .shortcut(let name): L("Rodar o atalho “%@”", name)
        case .presentation(let on): on ? L("Ligar o modo apresentação") : L("Desligar o modo apresentação")
        }
    }

    var icon: String {
        switch self {
        case .profile: "square.stack.3d.up.fill"
        case .keepAwake: "cup.and.saucer.fill"
        case .mic(let m): m ? "mic.slash.fill" : "mic.fill"
        case .dark(let on): on ? "moon.fill" : "sun.max.fill"
        case .openApp: "app.fill"
        case .brightness: "sun.max.fill"
        case .clipboardPaused(let on): on ? "pause.circle.fill" : "play.circle.fill"
        case .quitApps: "xmark.circle.fill"
        case .shortcut: "square.stack.3d.forward.dottedline.fill"
        case .presentation: "play.rectangle.fill"
        }
    }
}

// MARK: Motor

@MainActor
final class AutomationStore: ObservableObject {
    static let shared = AutomationStore()
    @Published private(set) var rules: [Automation] = []
    private var url: URL?
    private weak var toolbox: Toolbox?
    private var lastAC: Bool?
    private var lastPercent: Int?
    private var lastScreens = NSScreen.screens.count
    private var lastMinute = -1
    private var firedMeetings = Set<String>()
    private var observers: [Any] = []

    private init() {}

    func load(dir: URL) {
        url = dir.appendingPathComponent("automations.json")
        if let url, let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Automation].self, from: data) {
            rules = list
        }
    }

    func demo() {
        url = nil
        let profile = ProfileStore.shared.profiles.first?.id
        rules = [
            Automation(trigger: .time(hour: 9, minute: 0, weekdays: [2, 3, 4, 5, 6]),
                       actions: profile.map { [.profile($0)] } ?? [.keepAwake(true)],
                       lastRun: Date().addingTimeInterval(-3600 * 5), lastResult: "ok"),
            Automation(trigger: .power(plugged: false), actions: [.brightness(60), .keepAwake(false)]),
            Automation(trigger: .app(bundleID: "us.zoom.xos", name: "zoom.us", opened: true), actions: [.keepAwake(true), .mic(muted: true)]),
        ]
    }

    func rule(_ id: UUID) -> Automation? { rules.first { $0.id == id } }

    func upsert(_ r: Automation) {
        if let i = rules.firstIndex(where: { $0.id == r.id }) { rules[i] = r } else { rules.append(r) }
        save()
    }

    func delete(_ id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Gatilhos

    func start(toolbox: Toolbox) {
        self.toolbox = toolbox
        let ws = NSWorkspace.shared.notificationCenter
        for (name, opened) in [(NSWorkspace.didLaunchApplicationNotification, true), (NSWorkspace.didTerminateApplicationNotification, false)] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated {
                    guard let self, let bundle else { return }
                    self.fire { if case .app(let b, _, let o) = $0 { b == bundle && o == opened } else { false } }
                }
            })
        }
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire { $0 == .wake } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let count = NSScreen.screens.count
                defer { self.lastScreens = count }
                guard count != self.lastScreens else { return }
                let connected = count > self.lastScreens
                self.fire { if case .display(let c) = $0 { c == connected } else { false } }
            }
        })
    }

    /// A cada leitura do monitor (2 s): horário, carregador e bateria
    func tick(_ m: SystemMonitor) {
        let now = Date()
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute, .weekday], from: now)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if minute != lastMinute {
            lastMinute = minute
            fire { if case .time(let h, let mm, let days) = $0 { h * 60 + mm == minute && days.contains(c.weekday ?? 0) } else { false } }
            checkMeeting(now)
        }
        guard let b = m.battery else { return }
        if let lastAC, lastAC != b.onAC {
            fire { if case .power(let p) = $0 { p == b.onAC } else { false } }
        }
        if let lastPercent, !b.onAC {
            // Só ao cruzar o limite para baixo
            fire { if case .batteryBelow(let p) = $0 { lastPercent >= p && b.percent < p } else { false } }
        }
        lastAC = b.onAC
        lastPercent = b.percent
    }

    /// "N min antes": confere a próxima reunião a cada virada de minuto, uma vez por reunião e regra
    private func checkMeeting(_ now: Date) {
        guard let m = MeetingStore.shared.next else { return }
        let left = Int(ceil(m.start.timeIntervalSince(now) / 60))
        guard left >= 0 else { return }
        for r in rules where r.enabled {
            guard case .meeting(let before) = r.trigger, before == left else { continue }
            let key = "\(r.id)|\(m.id)|\(m.start.timeIntervalSince1970)"
            guard firedMeetings.insert(key).inserted else { continue }
            run(r)
        }
    }

    /// Ao ligar ou desligar o modo apresentação (para, por exemplo, rodar um atalho de Não Perturbe)
    func presentationChanged(started: Bool) {
        fire { $0 == .presentation(started: started) }
    }

    /// Chamado pelo timer de foco
    func focusChanged(started: Bool) {
        fire { $0 == .focus(started: started) }
    }

    private func fire(_ matches: (Automation.Trigger) -> Bool) {
        for r in rules where r.enabled && matches(r.trigger) {
            // No máximo uma vez por minuto: evita laços (uma ação que dispara a própria regra)
            if let last = r.lastRun, Date().timeIntervalSince(last) < 60 { continue }
            run(r)
        }
    }

    // MARK: Ações

    /// Executa as ações em ordem e guarda o resultado. `test`: veio do botão "Testar agora".
    func run(_ rule: Automation, test: Bool = false) {
        guard let tb = toolbox else { return }
        var failed: [String] = []
        for a in rule.actions {
            switch a {
            case .profile(let id):
                if let p = ProfileStore.shared.profile(id) { ProfileStore.shared.activate(p, toolbox: tb) } else { failed.append(a.title) }
            case .keepAwake(let on):
                if tb.keepAwake != on { tb.setKeepAwake(on) }
            case .mic(let muted):
                if tb.micMuted != muted { tb.toggleMic() }
            case .dark(let on):
                if tb.darkMode != on { tb.toggleDarkMode() }
            case .openApp(let path):
                if FileManager.default.fileExists(atPath: path) {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = false
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config)
                } else { failed.append(a.title) }
            case .brightness(let v):
                tb.displays.refresh()
                let screens = tb.displays.screens.filter { $0.kind != .unsupported }
                if screens.isEmpty { failed.append(a.title) }
                for s in screens { tb.displays.set(Double(v) / 100, for: s.id) }
            case .clipboardPaused(let on):
                on ? ClipboardManager.pause(minutes: nil) : ClipboardManager.resume()
            case .quitApps:
                AppControl.quitAll()
            case .shortcut(let name):
                Shortcuts.run(name)
            case .presentation(let on):
                PresentationMode.shared.set(on)
            }
        }
        var r = rule
        r.lastRun = Date()
        r.lastResult = failed.isEmpty ? "ok" : L("Falhou: %@", failed.joined(separator: ", "))
        if let i = rules.firstIndex(where: { $0.id == r.id }) { rules[i] = r; save() }
        // O perfil já mostra o próprio aviso
        let hasProfile = rule.actions.contains { if case .profile = $0 { true } else { false } }
        if (rule.notify || test) && !hasProfile {
            HUD.show(icon: failed.isEmpty ? "wand.and.stars" : "exclamationmark.triangle.fill",
                     color: failed.isEmpty ? .indigo : .orange, text: rule.trigger.title)
        }
    }
}

// MARK: Telas

/// Seção "Automações" na aba Ações
struct AutomationsSection: View {
    @ObservedObject var store: AutomationStore
    @Binding var editing: UUID?

    var body: some View {
        if store.rules.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Faça o Menew agir sozinho: às 9h ativar o perfil de trabalho, ao abrir o Zoom mutar o microfone, ao tirar da tomada baixar o brilho."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(title: L("Criar automação"), icon: "plus", primary: true) { create() }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(store.rules.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52) }
                    row(r)
                }
                Rectangle().fill(Theme.cardStroke).frame(height: 0.5)
                Button { create() } label: {
                    Label(L("Criar automação"), systemImage: "plus")
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

    private func row(_ r: Automation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.trigger.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(r.enabled ? Color.white : Color.secondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(r.enabled ? AnyShapeStyle(Color.teal.gradient) : AnyShapeStyle(Color.primary.opacity(0.08))))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.trigger.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(r.actions.isEmpty ? L("Nenhuma ação") : r.actions.map(\.title).joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            IconButton(icon: "pencil", help: L("Editar automação")) { editing = r.id }
            Toggle(r.trigger.title, isOn: Binding(get: { r.enabled }, set: { on in var x = r; x.enabled = on; store.upsert(x) }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden().tint(.teal)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .opacity(r.enabled ? 1 : 0.7)
    }

    private func create() {
        let r = Automation.default
        store.upsert(r)
        editing = r.id
    }
}

/// Editor de uma automação, no lugar da aba Ações
struct AutomationEditor: View {
    @ObservedObject var store: AutomationStore
    @ObservedObject var profiles = ProfileStore.shared
    @State var rule: Automation
    var onClose: () -> Void
    @State private var shortcuts: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { onClose() } label: {
                        Label(L("Ações"), systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    Spacer()
                    PillButton(title: L("Testar agora"), icon: "play.fill", primary: true) {
                        store.upsert(rule)
                        store.run(rule, test: true)
                        if let r = store.rule(rule.id) { rule = r }
                    }
                    .disabled(rule.actions.isEmpty)
                }

                GlassSection(title: L("Quando")) {
                    SettingRow(title: L("Gatilho"), icon: rule.trigger.icon) {
                        Picker("", selection: Binding(get: { rule.trigger.kind }, set: { rule.trigger = .make($0) })) {
                            ForEach(Automation.Trigger.Kind.allCases.filter { $0 == .time || $0 == .app || $0 == .display || SystemMonitorInfo.hasBattery },
                                    id: \.self) { k in Text(Automation.Trigger.kindTitle(k)).tag(k) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    RowDivider()
                    triggerDetail
                }

                GlassSection(title: L("Fazer")) {
                    ForEach(Array(rule.actions.enumerated()), id: \.offset) { i, a in
                        if i > 0 { RowDivider(inset: 42) }
                        HStack(spacing: 10) {
                            Image(systemName: a.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.teal).frame(width: 20)
                            Text(a.title).font(.system(size: 12.5))
                            Spacer()
                            IconButton(icon: "minus.circle", help: L("Tirar ação")) { rule.actions.remove(at: i) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    if !rule.actions.isEmpty { RowDivider() }
                    addActionMenu
                }

                GlassSection(title: L("Opções")) {
                    ToggleRow(title: L("Ligada"), icon: "power", isOn: $rule.enabled)
                    RowDivider()
                    ToggleRow(title: L("Avisar na tela quando rodar"), icon: "bell", isOn: $rule.notify)
                    if let last = rule.lastRun {
                        RowDivider()
                        SettingRow(title: L("Última vez"), icon: rule.lastResult == "ok" ? "checkmark.circle" : "exclamationmark.triangle") {
                            Text(rule.lastResult == "ok" ? last.formatted(.relative(presentation: .named).locale(L10n.locale)) : (rule.lastResult ?? ""))
                                .font(.system(size: 11.5)).foregroundStyle(rule.lastResult == "ok" ? Color.secondary : Color.orange)
                                .lineLimit(2).multilineTextAlignment(.trailing)
                        }
                    }
                }

                Button(role: .destructive) {
                    store.delete(rule.id)
                    onClose()
                } label: {
                    Label(L("Apagar automação"), systemImage: "trash").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(.red).padding(.leading, 4)
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .noLiquidGlass()
        .scrollIndicators(.never)
        .onChange(of: rule) { _, r in store.upsert(r) }
        .task { shortcuts = await Shortcuts.list() }
    }

    @ViewBuilder private var triggerDetail: some View {
        switch rule.trigger {
        case .time(let h, let m, let days):
            SettingRow(title: L("Horário")) {
                DatePicker("", selection: Binding(
                    get: { Calendar.current.date(from: DateComponents(hour: h, minute: m)) ?? Date() },
                    set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        rule.trigger = .time(hour: c.hour ?? 0, minute: c.minute ?? 0, weekdays: days)
                    }), displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
            }
            RowDivider()
            HStack(spacing: 5) {
                let symbols = Calendar.current.veryShortWeekdaySymbols
                // Segunda primeiro
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                    let on = days.contains(d)
                    Button {
                        var s = days
                        if on { s.remove(d) } else { s.insert(d) }
                        if !s.isEmpty { rule.trigger = .time(hour: h, minute: m, weekdays: s) }
                    } label: {
                        Text(symbols[d - 1]).font(.system(size: 11.5, weight: .semibold))
                            .frame(width: 30, height: 26)
                            .foregroundStyle(on ? Color.white : Color.secondary)
                            .background(Circle().fill(on ? Color.teal : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[d - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        case .power(let plugged):
            SettingRow(title: L("Quando o carregador for")) {
                Picker("", selection: Binding(get: { plugged }, set: { rule.trigger = .power(plugged: $0) })) {
                    Text(L("conectado")).tag(true)
                    Text(L("desconectado")).tag(false)
                }
                .labelsHidden().fixedSize()
            }
        case .batteryBelow(let p):
            SettingRow(title: L("Abaixo de %d%%", p)) {
                GlassStepper(value: Binding(get: { p }, set: { rule.trigger = .batteryBelow($0) }), range: 5...90, step: 5)
            }
        case .app(let bundle, let name, let opened):
            SettingRow(title: L("App")) {
                Menu(name.isEmpty ? L("Escolher…") : name) {
                    ForEach(AppIndex.all(), id: \.path) { app in
                        Button(app.name) {
                            let b = Bundle(path: app.path)?.bundleIdentifier ?? ""
                            rule.trigger = .app(bundleID: b, name: app.name, opened: opened)
                        }
                    }
                }
                .fixedSize()
            }
            RowDivider()
            SettingRow(title: L("Quando ele")) {
                Picker("", selection: Binding(get: { opened }, set: { rule.trigger = .app(bundleID: bundle, name: name, opened: $0) })) {
                    Text(L("abrir")).tag(true)
                    Text(L("fechar")).tag(false)
                }
                .labelsHidden().fixedSize()
            }
        case .display(let connected):
            SettingRow(title: L("Quando um monitor for")) {
                Picker("", selection: Binding(get: { connected }, set: { rule.trigger = .display(connected: $0) })) {
                    Text(L("conectado")).tag(true)
                    Text(L("desconectado")).tag(false)
                }
                .labelsHidden().fixedSize()
            }
        case .meeting(let before):
            SettingRow(title: L("Quando")) {
                Picker("", selection: Binding(get: { before }, set: { rule.trigger = .meeting(minutesBefore: $0) })) {
                    Text(L("na hora")).tag(0)
                    ForEach([1, 5, 10, 15], id: \.self) { m in Text(L("%d min antes", m)).tag(m) }
                }
                .labelsHidden().fixedSize()
            }
            if !MeetingStore.shared.isOn {
                RowDivider()
                Text(L("Ligue “Mostrar a próxima reunião” em Ajustes → Calendário para este gatilho funcionar."))
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        case .focus(let started):
            SettingRow(title: L("Quando o foco")) {
                Picker("", selection: Binding(get: { started }, set: { rule.trigger = .focus(started: $0) })) {
                    Text(L("começar")).tag(true)
                    Text(L("terminar")).tag(false)
                }
                .labelsHidden().fixedSize()
            }
        case .presentation(let started):
            SettingRow(title: L("Quando o modo apresentação")) {
                Picker("", selection: Binding(get: { started }, set: { rule.trigger = .presentation(started: $0) })) {
                    Text(L("ligar")).tag(true)
                    Text(L("desligar")).tag(false)
                }
                .labelsHidden().fixedSize()
            }
        case .wake:
            Text(L("Ao voltar do repouso, por exemplo quando você abre a tampa."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private var addActionMenu: some View {
        Menu {
            if !profiles.profiles.isEmpty {
                Menu(L("Ativar um perfil")) {
                    ForEach(profiles.profiles) { p in Button(p.name) { add(.profile(p.id)) } }
                }
            }
            Menu(L("Manter acordado")) {
                Button(L("Ligar")) { add(.keepAwake(true)) }
                Button(L("Desligar")) { add(.keepAwake(false)) }
            }
            Menu(L("Microfone")) {
                Button(L("Mutar")) { add(.mic(muted: true)) }
                Button(L("Ligar")) { add(.mic(muted: false)) }
            }
            Menu(L("Aparência")) {
                Button(L("Claro")) { add(.dark(false)) }
                Button(L("Escuro")) { add(.dark(true)) }
            }
            Menu(L("Brilho")) {
                ForEach([25, 50, 75, 100], id: \.self) { v in Button("\(v)%") { add(.brightness(v)) } }
            }
            Menu(L("Clipboard")) {
                Button(L("Pausar captura")) { add(.clipboardPaused(true)) }
                Button(L("Retomar captura")) { add(.clipboardPaused(false)) }
            }
            Button(L("Fechar todos os apps")) { add(.quitApps) }
            Menu(L("Modo apresentação")) {
                Button(L("Ligar")) { add(.presentation(true)) }
                Button(L("Desligar")) { add(.presentation(false)) }
            }
            Menu(L("Rodar um atalho")) {
                if shortcuts.isEmpty {
                    Text(L("Nenhum atalho no app Atalhos"))
                } else {
                    ForEach(shortcuts, id: \.self) { s in Button(s) { add(.shortcut(name: s)) } }
                }
            }
            Menu(L("Abrir um app")) {
                ForEach(AppIndex.all(), id: \.path) { app in Button(app.name) { add(.openApp(path: app.path)) } }
            }
        } label: {
            Label(L("Adicionar ação"), systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .foregroundStyle(Color.accentColor)
    }

    private func add(_ a: Automation.Action) {
        if !rule.actions.contains(a) { rule.actions.append(a) }
    }
}

/// Os atalhos do app Atalhos, pela ferramenta `shortcuts` do próprio macOS
enum Shortcuts {
    static func list() async -> [String] {
        await Task.detached {
            Shell.run("/usr/bin/shortcuts", ["list"]).split(separator: "\n").map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.sorted()
        }.value
    }

    /// Roda sem esperar; avisa só se falhar
    @MainActor static func run(_ name: String) {
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["run", name]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            let ok = (try? p.run()) != nil && { p.waitUntilExit(); return p.terminationStatus == 0 }()
            if !ok {
                await MainActor.run {
                    HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("O atalho “%@” falhou", name), duration: 2.5)
                }
            }
        }
    }
}
