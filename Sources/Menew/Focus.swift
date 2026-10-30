import AppKit
import SwiftUI
import UserNotifications

/// Timer de foco (pomodoro ou livre). O tempo aparece na barra de menus; ao começar, pode silenciar o
/// microfone, manter o Mac acordado e pausar o clipboard, e tudo volta como estava no fim.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    enum Phase { case focus, rest }

    static let muteKey = "focusMuteMic", awakeKey = "focusKeepAwake", clipKey = "focusPauseClipboard", breaksKey = "focusBreaks"

    @Published private(set) var phase: Phase?
    @Published private(set) var startedAt = Date()
    @Published private(set) var endsAt = Date()

    private weak var toolbox: Toolbox?
    private var timer: Timer?
    // O que o foco ligou, para desfazer só isso no fim
    private var mutedMic = false, keptAwake = false, pausedClipboard = false

    var isRunning: Bool { phase != nil }

    func attach(_ toolbox: Toolbox) { self.toolbox = toolbox }

    func start(minutes: Int) {
        stop(silently: true)
        let d = UserDefaults.standard
        if let tb = toolbox {
            if d.bool(forKey: Self.muteKey), !tb.micMuted { mutedMic = tb.toggleMic() }
            if d.object(forKey: Self.awakeKey) == nil || d.bool(forKey: Self.awakeKey), !tb.keepAwake {
                tb.setKeepAwake(true, minutes: minutes)
                keptAwake = tb.keepAwake
            }
        }
        if d.bool(forKey: Self.clipKey), !ClipboardManager.isPaused {
            ClipboardManager.pause(minutes: minutes)
            pausedClipboard = true
        }
        run(.focus, minutes: minutes)
        HUD.show(icon: "timer", color: .red, text: L("Foco por %d min", minutes))
    }

    func extend(minutes: Int = 5) {
        guard isRunning else { return }
        endsAt = max(endsAt, Date()).addingTimeInterval(TimeInterval(minutes * 60))
        schedule()
    }

    /// Parar antes da hora: desfaz o que o foco ligou, sem pausa nem aviso
    func stop(silently: Bool = false) {
        guard isRunning else { return }
        timer?.invalidate(); timer = nil
        restore()
        phase = nil
        if !silently { HUD.show(icon: "timer", color: .secondary, text: L("Foco encerrado")) }
    }

    private func run(_ p: Phase, minutes: Int) {
        phase = p
        startedAt = Date()
        endsAt = startedAt.addingTimeInterval(TimeInterval(minutes * 60))
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(endsAt.timeIntervalSinceNow, 0), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        }
    }

    private func finished() {
        timer = nil
        NSSound(named: "Glass")?.play()
        if phase == .focus {
            restore()
            let breaks = UserDefaults.standard.object(forKey: Self.breaksKey) == nil || UserDefaults.standard.bool(forKey: Self.breaksKey)
            notify(L("Foco concluído"), breaks ? L("Hora de uma pausa de 5 minutos.") : L("Bom trabalho!"))
            HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Foco concluído"))
            if breaks { run(.rest, minutes: 5) } else { phase = nil }
        } else {
            phase = nil
            notify(L("Pausa encerrada"), L("Pronto para outro foco?"))
            HUD.show(icon: "cup.and.saucer.fill", color: .orange, text: L("Pausa encerrada"))
        }
    }

    private func restore() {
        if let tb = toolbox {
            if mutedMic, tb.micMuted { tb.toggleMic() }
            if keptAwake, tb.keepAwake { tb.setKeepAwake(false) }
        }
        if pausedClipboard { ClipboardManager.resume() }
        mutedMic = false; keptAwake = false; pausedClipboard = false
    }

    private func notify(_ title: String, _ body: String) {
        guard let center = UNUserNotificationCenter.currentIfBundled else { return }
        center.delegate = Alerts.shared
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        center.add(UNNotificationRequest(identifier: "focus", content: c, trigger: nil))
    }

    /// Tempo restante na barra de menus: minutos, e segundos no último minuto
    var segment: StatusSegment? {
        guard let phase else { return nil }
        let left = max(0, Int(endsAt.timeIntervalSinceNow.rounded(.up)))
        let value = left >= 60 ? "\((left + 59) / 60)m" : "\(left)s"
        return .stat(phase == .focus ? L("FOCO") : L("PAUSA"), value)
    }
}

/// Cartão do foco na aba Ações
struct FocusCard: View {
    @ObservedObject var focus = FocusTimer.shared
    @AppStorage(FocusTimer.muteKey) private var mute = false
    @AppStorage(FocusTimer.awakeKey) private var awake = true
    @AppStorage(FocusTimer.clipKey) private var pauseClip = false
    @AppStorage(FocusTimer.breaksKey) private var breaks = true

    var body: some View {
        Group {
            if let phase = focus.phase { running(phase) } else { idle }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass()
    }

    private var idle: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.red.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Timer de foco")).font(.system(size: 12.5, weight: .semibold))
                Text(L("Com pausa no fim")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            PillButton(title: L("25 min"), icon: "play.fill", primary: true) { focus.start(minutes: 25) }
            Menu {
                ForEach([15, 45, 50, 90], id: \.self) { m in
                    Button(L("%d minutos", m)) { focus.start(minutes: m) }
                }
                Divider()
                Toggle(L("Mutar o microfone"), isOn: $mute)
                Toggle(L("Manter o Mac acordado"), isOn: $awake)
                Toggle(L("Pausar o clipboard"), isOn: $pauseClip)
                Toggle(L("Pausa de 5 min no fim"), isOn: $breaks)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
            .help(L("Outros tempos e opções"))
        }
    }

    private func running(_ phase: FocusTimer.Phase) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let total = max(focus.endsAt.timeIntervalSince(focus.startedAt), 1)
            let left = max(0, focus.endsAt.timeIntervalSince(ctx.date))
            let color: Color = phase == .focus ? .red : .green
            HStack(spacing: 12) {
                Ring(fraction: 1 - left / total, color: color, lineWidth: 4).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(phase == .focus ? L("Em foco") : L("Pausa")).font(.system(size: 12.5, weight: .semibold))
                    Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
                        .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                PillButton(title: L("+5 min"), icon: "plus") { focus.extend() }
                PillButton(title: L("Parar"), icon: "stop.fill") { focus.stop() }
            }
        }
    }
}
