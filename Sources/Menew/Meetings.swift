import AppKit
import EventKit
import SwiftUI
import UserNotifications

struct Meeting: Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var link: URL?
    var color: Color
    /// Tem outras pessoas convidadas (sem ninguém, é um bloqueio na agenda: almoço, ginástica, foco)
    var withOthers = false
}

/// Próxima reunião do app Calendário. Desligado por padrão; só pede acesso ao Calendário quando você liga.
/// Tudo é lido no Mac (EventKit), sem conta e sem internet.
@MainActor
final class MeetingStore: ObservableObject {
    static let shared = MeetingStore()
    static let key = "meetings"
    static let remindKey = "meetingsRemind"
    static let workStartKey = "workStartHour"
    static let workEndKey = "workEndHour"

    @Published private(set) var next: Meeting?
    /// Reuniões de hoje (as que já passaram também), para a agenda do dia
    @Published private(set) var today: [Meeting] = []
    @Published private(set) var denied = false

    private let store = EKEventStore()
    private var timer: Timer?
    /// Dispara no segundo em que uma reunião começa ou termina, para a troca não esperar a leitura do minuto
    private var edgeTimer: Timer?
    private var observer: Any?
    private var wakeObservers: [Any] = []
    /// Reunião em que você clicou Entrar: o aviso do notch some
    private(set) var joinedID: String?
    /// Avisos do notch dispensados nesta ocorrência (o mesmo evento repetido tem o mesmo id, então vai com o horário)
    private var dismissed: Set<String> = []

    // MARK: Avisos do notch

    static let onlyRealKey = "notch.onlyRealMeetings"
    static let mutedKey = "notch.mutedMeetingTitles"
    /// Só avisa de reuniões com link ou com outras pessoas (ligado por padrão)
    static var onlyReal: Bool { UserDefaults.standard.object(forKey: onlyRealKey) as? Bool ?? true }
    /// Títulos que nunca avisam no notch ("Almoço", "Ginástica laboral")
    static var mutedTitles: [String] {
        get { UserDefaults.standard.stringArray(forKey: mutedKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: mutedKey) }
    }

    static func occurrence(_ m: Meeting) -> String { "\(m.id)|\(Int(m.start.timeIntervalSince1970))" }

    /// O aviso dessa reunião não aparece no notch
    nonisolated static func notchIgnores(_ m: Meeting, dismissed: Set<String>, muted: [String], onlyReal: Bool) -> Bool {
        if dismissed.contains("\(m.id)|\(Int(m.start.timeIntervalSince1970))") { return true }
        let title = PaletteSearch.fold(m.title.trimmingCharacters(in: .whitespaces))
        if muted.contains(where: { PaletteSearch.fold($0) == title }) { return true }
        return onlyReal && m.link == nil && !m.withOthers
    }

    func notchIgnores(_ m: Meeting) -> Bool {
        Self.notchIgnores(m, dismissed: dismissed, muted: Self.mutedTitles, onlyReal: Self.onlyReal)
    }

    /// Some com o aviso desta vez
    func dismiss(_ m: Meeting) {
        dismissed.insert(Self.occurrence(m))
        NotchCenter.shared.update()
    }

    /// Nunca mais avisa de reuniões com esse título
    func mute(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !Self.mutedTitles.contains(t) else { return }
        Self.mutedTitles.append(t)
        NotchCenter.shared.update()
    }
    private var demo = false

    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.key) }

    /// Liga ou desliga conforme o ajuste. Pede o acesso só na primeira vez que liga.
    func refreshEnabled() {
        guard !demo else { return }
        guard isOn else { stop(); return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            denied = false
            start()
        case .notDetermined:
            store.requestFullAccessToEvents { granted, _ in
                Task { @MainActor in
                    self.denied = !granted
                    if granted { self.start() }
                }
            }
        default:
            denied = true
            stop()
        }
    }

    private func start() {
        guard timer == nil else { return reload() }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // Uma leitura por minuto, mais uma no segundo exato de cada início e fim (edgeTimer)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // Ao acordar o Mac ou mudar o relógio, relê na hora
        let ws = NSWorkspace.shared.notificationCenter
        wakeObservers = [
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
            NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
        ]
        reload()
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        edgeTimer?.invalidate(); edgeTimer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        for o in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(o); NotificationCenter.default.removeObserver(o) }
        wakeObservers = []
        next = nil
        UNUserNotificationCenter.currentIfBundled?.removePendingNotificationRequests(withIdentifiers: ["meeting"])
    }

    func reload() {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3 * 3600),
                                                 end: now.addingTimeInterval(12 * 3600), calendars: nil)
        let upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && $0.endDate > now && !Self.declined($0) }
            .sorted { $0.startDate < $1.startDate }
            .map(Self.meeting)
        let meeting = Self.current(upcoming, now: now)
        if meeting != next { next = meeting }
        let day = Calendar.current.startOfDay(for: now)
        let list = store.events(matching: store.predicateForEvents(withStart: day, end: day.addingTimeInterval(86400), calendars: nil))
            .filter { !$0.isAllDay && $0.status != .canceled && !Self.declined($0) }
            .sorted { $0.startDate < $1.startDate }
            .map(Self.meeting)
        if list != today { today = list }
        scheduleEdge(upcoming, now: now)
        scheduleReminder()
    }

    /// A reunião da faixa: a que está acontecendo, mas, nos 2 últimos minutos dela, a seguinte se já vem logo
    /// depois (reuniões coladas: às 08:59 já mostra a das 09:00)
    static func current(_ upcoming: [Meeting], now: Date) -> Meeting? {
        guard let first = upcoming.first else { return nil }
        if first.start <= now, first.end.timeIntervalSince(now) <= 120,
           let following = upcoming.dropFirst().first(where: { $0.start >= first.end.addingTimeInterval(-60) }),
           following.start.timeIntervalSince(first.end) <= 120 {
            return following
        }
        return first
    }

    /// Agenda uma releitura para o próximo início, fim ou troca de reunião
    private func scheduleEdge(_ upcoming: [Meeting], now: Date) {
        edgeTimer?.invalidate()
        let edges = upcoming.flatMap { [$0.start, $0.end, $0.end.addingTimeInterval(-120)] }.filter { $0 > now }
        guard let edge = edges.min(), edge.timeIntervalSince(now) < 3600 else { edgeTimer = nil; return }
        let t = Timer(fire: edge.addingTimeInterval(0.2), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
                NotchCenter.shared.update()
            }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        edgeTimer = t
    }

    func join() {
        guard let m = next else { return }
        joinedID = m.id
        if let url = m.link { NSWorkspace.shared.open(url) }
        NotchCenter.shared.update()
    }

    private static func meeting(_ e: EKEvent) -> Meeting {
        Meeting(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "", start: e.startDate, end: e.endDate,
                link: link(in: e), color: e.calendar.map { Color(cgColor: $0.cgColor) } ?? Theme.indigo,
                withOthers: (e.attendees ?? []).contains { !$0.isCurrentUser })
    }

    /// Abre a chamada, se tiver link, ou o evento no Calendário
    func open(_ m: Meeting) {
        if m.id == next?.id { joinedID = m.id; NotchCenter.shared.update() }
        if let url = m.link { NSWorkspace.shared.open(url); return }
        let t = Int(m.start.timeIntervalSinceReferenceDate)
        if let url = URL(string: "ical://ekevent/\(m.id)?method=show&options=more") ?? URL(string: "calshow:\(t)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Horários livres

    /// Texto pronto para mandar a alguém: os horários livres nos próximos dias úteis, dentro do horário de trabalho
    func freeSlotsText(days: Int = 5) -> String {
        let d = UserDefaults.standard
        let startHour = d.object(forKey: Self.workStartKey) as? Int ?? 9
        let endHour = d.object(forKey: Self.workEndKey) as? Int ?? 18
        let cal = Calendar.current
        let now = Date()
        var lines: [String] = []
        var day = cal.startOfDay(for: now)
        var counted = 0
        while counted < days {
            defer { day = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400) }
            let weekday = cal.component(.weekday, from: day)
            guard weekday != 1 && weekday != 7 else { continue }
            counted += 1
            guard var from = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
                  let to = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: day), to > now else { continue }
            // Hoje: só a partir da próxima meia hora cheia
            if from < now {
                var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
                let past30 = (c.minute ?? 0) >= 30
                c.minute = past30 ? 0 : 30
                if let rounded = cal.date(from: c) { from = past30 ? rounded.addingTimeInterval(3600) : rounded }
                guard from < to else { continue }
            }
            let busy = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
                .filter { !$0.isAllDay && $0.status != .canceled && $0.availability != .free && !Self.declined($0) }
                .map { ($0.startDate!, $0.endDate!) }
                .sorted { $0.0 < $1.0 }
            var free: [(Date, Date)] = []
            var cursor = from
            for (s, e) in busy {
                if s > cursor { free.append((cursor, min(s, to))) }
                cursor = max(cursor, e)
                if cursor >= to { break }
            }
            if cursor < to { free.append((cursor, to)) }
            let slots = free.filter { $0.1.timeIntervalSince($0.0) >= 30 * 60 }
            guard !slots.isEmpty else { continue }
            let time = Date.FormatStyle.dateTime.hour().minute().locale(L10n.locale)
            let label = day.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).locale(L10n.locale))
            lines.append(label + ": " + slots.map { $0.0.formatted(time) + "–" + $0.1.formatted(time) }.joined(separator: ", "))
        }
        guard !lines.isEmpty else { return L("Sem horários livres nos próximos dias úteis.") }
        return L("Meus horários livres:") + "\n" + lines.joined(separator: "\n")
    }

    func copyFreeSlots() {
        guard isOn, !denied else {
            HUD.show(icon: "calendar.badge.exclamationmark", color: .orange,
                     text: L("Ligue o Calendário em Ajustes → Calendário"), duration: 2.5)
            return
        }
        let text = freeSlotsText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        HUD.show(icon: "calendar.badge.checkmark", color: .green, text: L("Horários livres copiados"))
    }

    private static func declined(_ e: EKEvent) -> Bool {
        e.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    // MARK: Link da chamada

    private static let linkPattern = try! NSRegularExpression(pattern:
        #"https://[\w.-]*(zoom\.us/(j|my|w)/|meet\.google\.com/|teams\.microsoft\.com/l/meetup-join/|teams\.live\.com/meet/|[\w-]+\.webex\.com/|whereby\.com/|meet\.jit\.si/|chime\.aws/|facetime\.apple\.com/join)[^\s<>"')\]]*"#,
        options: .caseInsensitive)

    /// Link de Zoom, Meet, Teams… num texto qualquer (o clipboard esperto usa)
    static func meetingLink(in t: String) -> URL? {
        let range = NSRange(t.startIndex..., in: t)
        guard let m = linkPattern.firstMatch(in: t, range: range), let r = Range(m.range, in: t) else { return nil }
        return URL(string: String(t[r]))
    }

    /// Procura o link de Zoom, Meet, Teams, Webex… na URL, no local e nas notas do evento
    static func link(in e: EKEvent) -> URL? {
        let texts = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }
        for t in texts {
            let range = NSRange(t.startIndex..., in: t)
            if let m = linkPattern.firstMatch(in: t, range: range), let r = Range(m.range, in: t) {
                return URL(string: String(t[r]))
            }
        }
        return nil
    }

    // MARK: Aviso 1 minuto antes

    private func scheduleReminder() {
        guard let center = UNUserNotificationCenter.currentIfBundled else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["meeting"])
        guard UserDefaults.standard.bool(forKey: Self.remindKey), let m = next else { return }
        let fire = m.start.addingTimeInterval(-60)
        guard fire > Date() else { return }
        center.delegate = Alerts.shared
        let content = UNMutableNotificationContent()
        content.title = m.title
        content.body = m.link != nil ? L("Começa em 1 minuto. Clique para entrar.") : L("Começa em 1 minuto.")
        content.sound = .default
        if let link = m.link { content.userInfo = ["url": link.absoluteString] }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        center.add(UNNotificationRequest(identifier: "meeting", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    /// Reunião de mentira para as capturas de tela
    func showDemo(startsIn: TimeInterval = 12 * 60 + 30) {
        demo = true
        next = Meeting(id: "demo", title: L("Alinhamento semanal"), start: Date().addingTimeInterval(startsIn),
                       end: Date().addingTimeInterval(42 * 60), link: URL(string: "https://zoom.us/j/1"), color: .orange)
        today = [
            Meeting(id: "d1", title: L("Daily"), start: Date().addingTimeInterval(-3 * 3600), end: Date().addingTimeInterval(-2.75 * 3600),
                    link: nil, color: .blue),
            next!,
            Meeting(id: "d3", title: L("Revisão do trimestre"), start: Date().addingTimeInterval(3 * 3600),
                    end: Date().addingTimeInterval(4 * 3600), link: nil, color: .purple),
        ]
    }
}

extension UNUserNotificationCenter {
    /// Sem bundle (binário solto, testes) o UNUserNotificationCenter derruba o app
    static var currentIfBundled: UNUserNotificationCenter? { Bundle.main.bundleIdentifier == nil ? nil : .current() }
}

/// Faixa da próxima reunião no topo do menu
struct MeetingBanner: View {
    let meeting: Meeting
    var today: [Meeting] = []
    let onJoin: () -> Void
    @State private var expanded: Bool

    init(meeting: Meeting, today: [Meeting] = [], expanded: Bool = false, onJoin: @escaping () -> Void) {
        self.meeting = meeting
        self.today = today
        self.onJoin = onJoin
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(meeting.color).frame(width: 4, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meeting.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(when(ctx.date)).font(.system(size: 11)).foregroundStyle(soon(ctx.date) ? Color.orange : .secondary)
                    }
                    Spacer(minLength: 6)
                    if today.count > 1 {
                        Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                            HStack(spacing: 3) {
                                Text(L("Hoje · %d", today.count)).font(.system(size: 10.5, weight: .medium))
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                                    .rotationEffect(.degrees(expanded ? 180 : 0))
                            }
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L("Agenda de hoje"))
                    }
                    if meeting.link != nil {
                        PillButton(title: L("Entrar"), icon: "video.fill", primary: true, action: onJoin)
                    }
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(today, id: \.id) { m in
                            Button { MeetingStore.shared.open(m) } label: {
                                HStack(spacing: 8) {
                                    Text(m.start.formatted(.dateTime.hour().minute().locale(L10n.locale)))
                                        .font(.system(size: 11, weight: .medium)).monospacedDigit().frame(width: 52, alignment: .leading)
                                    Circle().fill(m.color).frame(width: 6, height: 6)
                                    Text(m.title).font(.system(size: 11.5)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    if m.link != nil { Image(systemName: "video.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                                }
                                .opacity(m.end < ctx.date ? 0.45 : 1)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Button { MeetingStore.shared.copyFreeSlots() } label: {
                            Label(L("Copiar meus horários livres"), systemImage: "calendar.badge.checkmark")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.violet)
                        }
                        .buttonStyle(.plain).padding(.top, 2)
                    }
                    .padding(.leading, 14)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass()
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    private func soon(_ now: Date) -> Bool { meeting.start.timeIntervalSince(now) < 5 * 60 }

    private func when(_ now: Date) -> String {
        let time = meeting.start.formatted(.dateTime.hour().minute().locale(L10n.locale))
        if meeting.start <= now { return L("Agora · até %@", meeting.end.formatted(.dateTime.hour().minute().locale(L10n.locale))) }
        let mins = Int(ceil(meeting.start.timeIntervalSince(now) / 60))
        if mins < 60 { return L("Em %d min · %@", mins, time) }
        if !Calendar.current.isDate(meeting.start, inSameDayAs: now) { return L("Amanhã às %@", time) }
        return L("Às %@", time)
    }
}

/// Ajustes → Calendário
struct MeetingsSection: View {
    @AppStorage(MeetingStore.key) private var on = false
    @AppStorage(MeetingStore.remindKey) private var remind = true
    @AppStorage(MeetingStore.workStartKey) private var workStart = 9
    @AppStorage(MeetingStore.workEndKey) private var workEnd = 18
    @ObservedObject private var store = MeetingStore.shared

    var body: some View {
        GlassSection(title: L("Calendário"),
                     footer: L("Lê o app Calendário no seu Mac (as contas que você já adicionou nele). Nada sai do Mac.")) {
            ToggleRow(title: L("Mostrar a próxima reunião"), detail: L("No topo do menu, com botão para entrar no Zoom, Meet ou Teams"),
                      icon: "calendar", isOn: $on)
                .onChange(of: on) { _, v in
                    store.refreshEnabled()
                    if v, remind { Alerts.shared.requestPermission { _ in } }
                }
            if on {
                RowDivider()
                SettingRow(title: L("Horário de trabalho"), detail: L("Para “Copiar meus horários livres”")) {
                    HStack(spacing: 4) {
                        Picker("", selection: $workStart) { ForEach(5...12, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                            .labelsHidden().fixedSize()
                        Text("–").foregroundStyle(.secondary)
                        Picker("", selection: $workEnd) { ForEach(13...23, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                            .labelsHidden().fixedSize()
                    }
                }
                RowDivider()
                ToggleRow(title: L("Avisar 1 minuto antes"), isOn: $remind)
                    .onChange(of: remind) { _, v in
                        if v { Alerts.shared.requestPermission { _ in store.reload() } } else { store.reload() }
                    }
            }
            if on, store.denied {
                RowDivider()
                SettingRow(title: L("O Menew não tem acesso ao Calendário."), icon: "calendar.badge.exclamationmark") {
                    PillButton(title: L("Abrir Ajustes")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
                .foregroundStyle(.orange)
            }
        }
    }
}
