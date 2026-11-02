import AppKit
import SwiftUI

/// Avisos ao vivo no notch: o que importa agora aparece dos dois lados da câmera, uma coisa por vez, por prioridade
/// (reunião chegando > gravação > aviso rápido > foco/timer > mic mudo). Some quando não há nada.
/// Em Macs sem notch, aparece como uma pílula no topo da tela (desligado por padrão).
@MainActor
final class NotchCenter: ObservableObject {
    static let shared = NotchCenter()
    static let key = "notchOn"

    enum Activity: Equatable {
        case meeting(title: String, start: Date, hasLink: Bool)
        case recording(since: Date)
        case flash(icon: String, color: Color, text: String)
        case focus(end: Date, rest: Bool)
        case timer(label: String, end: Date)
        case micMuted
    }

    @Published private(set) var activity: Activity?
    private var flash: (Activity, Date?)?
    private var panel: NSPanel?
    private var timer: Timer?
    private var muted = false
    private var lastMuteCheck = Date.distantPast

    /// Ligado por padrão só em Macs com notch
    var isOn: Bool { UserDefaults.standard.object(forKey: Self.key) as? Bool ?? Self.hasNotch }

    static var hasNotch: Bool { (NSScreen.screens.first?.safeAreaInsets.top ?? 0) > 0 }

    /// A tela com notch (a embutida); sem notch, a principal
    private static var screen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main }

    func refresh() {
        timer?.invalidate()
        timer = nil
        guard isOn else { activity = nil; panel?.orderOut(nil); return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { NotchCenter.shared.update() }
        }
        update()
    }

    /// Avisos do Menew ("Copiado", "Pensando…"): no notch, quando ele está ligado
    func show(icon: String, color: Color, text: String, duration: TimeInterval?) -> Bool {
        guard isOn else { return false }
        flash = (.flash(icon: icon, color: color, text: text), duration.map { Date().addingTimeInterval($0) })
        update()
        return true
    }

    /// Para as capturas de tela
    func showDemo(_ a: Activity) { activity = a }

    func hideFlash() {
        flash = nil
        update()
    }

    func update(now: Date = Date()) {
        if let (_, until) = flash, let until, until < now { flash = nil }
        if now.timeIntervalSince(lastMuteCheck) > 2 {
            lastMuteCheck = now
            // Só importa numa chamada: mic mudo com algum app usando o microfone
            muted = AudioControl.isMuted(input: true) && AudioControl.micInUse()
        }
        let next = Self.pick(now: now, flash: flash?.0, muted: muted)
        if next != activity {
            withAnimation(.spring(duration: 0.35)) { activity = next }
        }
        place()
    }

    /// A ordem de importância
    static func pick(now: Date, flash: Activity?, muted: Bool) -> Activity? {
        if let m = MeetingStore.shared.next, m.start > now.addingTimeInterval(-60), m.start.timeIntervalSince(now) <= 120 {
            return .meeting(title: m.title, start: m.start, hasLink: m.link != nil)
        }
        if ScreenRecorder.shared.isRecording { return .recording(since: ScreenRecorder.shared.started) }
        if let flash { return flash }
        let focus = FocusTimer.shared
        if focus.isRunning { return .focus(end: focus.endsAt, rest: focus.phase == .rest) }
        if let t = TimerStore.shared.active.min(by: { $0.end < $1.end }) { return .timer(label: t.label, end: t.end) }
        if muted { return .micMuted }
        return nil
    }

    // MARK: Janela

    /// Tamanho do notch (largura entre as duas metades da barra de menus e altura da barra)
    static func notchSize(_ s: NSScreen) -> CGSize {
        guard s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else { return CGSize(width: 0, height: 0) }
        return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
    }

    private func place() {
        guard let activity, let screen = Self.screen else { panel?.orderOut(nil); return }
        let notch = Self.notchSize(screen)
        let tall = { if case .meeting(_, _, true) = activity { return true }; if case .recording = activity { return true }; return false }()
        // Avisos e reuniões têm texto: um pouco mais de espaço dos lados
        let ear: CGFloat = { if case .flash = activity { return 210 }; if case .meeting = activity { return 150 }; return 115 }()
        let width = notch.width > 0 ? notch.width + ear * 2 : 300
        let height = (notch.height > 0 ? notch.height : 32) + (tall ? 38 : 0)
        let y = notch.height > 0 ? screen.frame.maxY - height : screen.visibleFrame.maxY - height - 6
        let frame = NSRect(x: screen.frame.midX - width / 2, y: y, width: width, height: height)
        let p = panel ?? makePanel()
        panel = p
        // Só aceita cliques quando há botão (Entrar, Parar); no resto, o clique passa para a barra de menus
        p.ignoresMouseEvents = !tall
        if p.frame != frame { p.setFrame(frame, display: true, animate: p.isVisible) }
        if !p.isVisible { p.orderFrontRegardless() }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Acima da barra de menus, para encostar no notch
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: NotchView(center: self, notch: Self.screen.map(Self.notchSize) ?? .zero))
        return p
    }
}

/// O desenho: preto como o notch, com cantos de baixo arredondados; à esquerda o ícone, à direita o valor
struct NotchView: View {
    @ObservedObject var center: NotchCenter
    let notch: CGSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if let a = center.activity {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        left(a).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
                        Color.clear.frame(width: notch.width)
                        right(a, now: ctx.date).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14)
                    }
                    .frame(height: notch.height > 0 ? notch.height : 32)
                    bottom(a)
                }
                .foregroundStyle(.white)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14).fill(.black))
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func left(_ a: NotchCenter.Activity) -> some View {
        switch a {
        case .meeting:
            Label { Text(L("Reunião")) } icon: { Image(systemName: "video.fill").foregroundStyle(.orange) }
                .font(.system(size: 12, weight: .semibold))
        case .recording:
            HStack(spacing: 6) { Circle().fill(.red).frame(width: 8, height: 8); Text(L("Gravando")).font(.system(size: 12, weight: .semibold)) }
        case .flash(let icon, let color, _):
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
        case .focus(_, let rest):
            Label(rest ? L("Pausa") : L("Foco"), systemImage: rest ? "cup.and.saucer.fill" : "scope").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(rest ? .green : .orange)
        case .timer(let label, _):
            Label(label.isEmpty ? L("Timer") : label, systemImage: "hourglass").font(.system(size: 12, weight: .semibold)).lineLimit(1)
        case .micMuted:
            Image(systemName: "mic.slash.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.red)
        }
    }

    @ViewBuilder private func right(_ a: NotchCenter.Activity, now: Date) -> some View {
        switch a {
        case .meeting(_, let start, _):
            Text(start > now ? L("em %@", Self.clock(start.timeIntervalSince(now))) : L("agora")).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        case .recording(let since):
            Text(Self.clock(now.timeIntervalSince(since))).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        case .flash(_, _, let text):
            Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        case .focus(let end, _), .timer(_, let end):
            Text(Self.clock(max(0, end.timeIntervalSince(now)))).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        case .micMuted:
            Text(L("Mic mudo")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.red)
        }
    }

    @ViewBuilder private func bottom(_ a: NotchCenter.Activity) -> some View {
        switch a {
        case .meeting(let title, _, true):
            // O nome inteiro cabe aqui embaixo, ao lado do botão
            HStack(spacing: 10) {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 6)
                Button { MeetingStore.shared.join() } label: {
                    Label(L("Entrar"), systemImage: "video.fill").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
        case .recording:
            Button { ScreenRecorder.shared.stop() } label: {
                Label(L("Parar"), systemImage: "stop.fill").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain).padding(.bottom, 8)
        default:
            EmptyView()
        }
    }

    /// 125 → "2:05"; 3725 → "1:02:05"
    static func clock(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}
