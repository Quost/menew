import AppKit
import Combine
import MenewShared
import WidgetKit

/// Escreve a cada minuto o que os widgets mostram (sistema, reuniões, timers, tempo de tela) num arquivo
/// do contêiner compartilhado e avisa o macOS quando algo muda. Tudo fica no Mac.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private var timer: Timer?
    private var bag: Set<AnyCancellable> = []
    private var lastSystemReload = Date.distantPast
    private var last: WidgetSnapshot?
    private weak var monitor: SystemMonitor?

    func start(monitor: SystemMonitor) {
        guard WidgetSnapshot.url != nil, !DemoMode.isOn else { return }
        self.monitor = monitor
        write()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { WidgetBridge.shared.write() }
        }
        // Reunião, timer ou foco mudou: os widgets mudam já, sem esperar o minuto
        let changes: [AnyPublisher<Void, Never>] = [
            MeetingStore.shared.$today.map { _ in () }.eraseToAnyPublisher(),
            TimerStore.shared.$active.map { _ in () }.eraseToAnyPublisher(),
            FocusTimer.shared.$phase.map { _ in () }.eraseToAnyPublisher(),
            ScreenTime.shared.$isOn.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes).dropFirst(changes.count).debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { _ in MainActor.assumeIsolated { WidgetBridge.shared.write(reloadAll: true) } }
            .store(in: &bag)
    }

    func write(reloadAll: Bool = false) {
        let s = snapshot()
        s.save()
        defer { last = s }
        if reloadAll || last?.meetings != s.meetings || last?.countdowns != s.countdowns || last?.meetingsOn != s.meetingsOn || last?.screenTimeOn != s.screenTimeOn {
            WidgetCenter.shared.reloadAllTimelines()
            lastSystemReload = Date()
        } else if Date().timeIntervalSince(lastSystemReload) > 5 * 60 {
            // Números do sistema e tempo de tela: no máximo a cada 5 minutos, para não gastar a cota do macOS
            WidgetCenter.shared.reloadTimelines(ofKind: "system")
            WidgetCenter.shared.reloadTimelines(ofKind: "screentime")
            lastSystemReload = Date()
        }
    }

    func snapshot(now: Date = Date()) -> WidgetSnapshot {
        var s = WidgetSnapshot(updated: now, lang: L10n.current.rawValue)
        if let m = monitor {
            s.cpu = m.cpu
            s.cpuHistory = Array(m.cpuHistory.suffix(60))
            s.memUsed = m.memUsed; s.memTotal = m.memTotal
            s.diskFree = m.diskFree; s.diskTotal = m.diskTotal
            s.battery = m.battery?.percent; s.charging = m.battery?.charging ?? false
        }
        let meetings = MeetingStore.shared
        s.meetingsOn = meetings.isOn
        s.meetings = meetings.today.filter { $0.end > now }.prefix(4).map {
            WidgetSnapshot.Meeting(title: $0.title, start: $0.start, end: $0.end, hasLink: $0.link != nil)
        }
        let focus = FocusTimer.shared
        if let phase = focus.phase {
            s.countdowns.append(.init(label: "", start: focus.startedAt, end: focus.endsAt, kind: phase == .rest ? .rest : .focus))
        }
        s.countdowns += TimerStore.shared.active.map { .init(label: $0.label, start: $0.started, end: $0.end, kind: $0.isAlarm ? .alarm : .timer) }
        let st = ScreenTime.shared
        s.screenTimeOn = st.isOn
        if st.isOn {
            let today = [ScreenTime.dayKey(now)]
            let cats = st.byCategory(today)
            s.screenFocus = cats[.focus] ?? 0
            s.screenNeutral = cats[.neutral] ?? 0
            s.screenDistraction = cats[.distraction] ?? 0
            s.screenTop = st.totals(today).prefix(3).map { .init(name: $0.name, seconds: $0.seconds) }
        }
        return s
    }
}
