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
}

/// Próxima reunião do app Calendário. Desligado por padrão; só pede acesso ao Calendário quando você liga.
/// Tudo é lido no Mac (EventKit), sem conta e sem internet.
@MainActor
final class MeetingStore: ObservableObject {
    static let shared = MeetingStore()
    static let key = "meetings"
    static let remindKey = "meetingsRemind"

    @Published private(set) var next: Meeting?
    @Published private(set) var denied = false

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: Any?
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
        // Uma leitura por minuto basta: a contagem regressiva é desenhada pela própria tela
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        next = nil
        UNUserNotificationCenter.currentIfBundled?.removePendingNotificationRequests(withIdentifiers: ["meeting"])
    }

    func reload() {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3 * 3600),
                                                 end: now.addingTimeInterval(12 * 3600), calendars: nil)
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && $0.endDate > now && !Self.declined($0) }
            .sorted { $0.startDate < $1.startDate }
            .first
        let meeting = event.map {
            Meeting(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "", start: $0.startDate, end: $0.endDate,
                    link: Self.link(in: $0), color: $0.calendar.map { Color(cgColor: $0.cgColor) } ?? Theme.indigo)
        }
        if meeting != next { next = meeting }
        scheduleReminder()
    }

    func join() {
        if let url = next?.link { NSWorkspace.shared.open(url) }
    }

    private static func declined(_ e: EKEvent) -> Bool {
        e.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    // MARK: Link da chamada

    private static let linkPattern = try! NSRegularExpression(pattern:
        #"https://[\w.-]*(zoom\.us/(j|my|w)/|meet\.google\.com/|teams\.microsoft\.com/l/meetup-join/|teams\.live\.com/meet/|[\w-]+\.webex\.com/|whereby\.com/|meet\.jit\.si/|chime\.aws/|facetime\.apple\.com/join)[^\s<>"')\]]*"#,
        options: .caseInsensitive)

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
    func showDemo() {
        demo = true
        next = Meeting(id: "demo", title: L("Alinhamento semanal"), start: Date().addingTimeInterval(12 * 60 + 30),
                       end: Date().addingTimeInterval(42 * 60), link: URL(string: "https://zoom.us/j/1"), color: .orange)
    }
}

extension UNUserNotificationCenter {
    /// Sem bundle (binário solto, testes) o UNUserNotificationCenter derruba o app
    static var currentIfBundled: UNUserNotificationCenter? { Bundle.main.bundleIdentifier == nil ? nil : .current() }
}

/// Faixa da próxima reunião no topo do menu
struct MeetingBanner: View {
    let meeting: Meeting
    let onJoin: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(meeting.color).frame(width: 4, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(when(ctx.date)).font(.system(size: 11)).foregroundStyle(soon(ctx.date) ? Color.orange : .secondary)
                }
                Spacer(minLength: 6)
                if meeting.link != nil {
                    PillButton(title: L("Entrar"), icon: "video.fill", primary: true, action: onJoin)
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
