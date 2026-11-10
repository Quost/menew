import AppKit
import SwiftUI

/// Avisos ao vivo no notch: o que importa agora aparece dos dois lados da câmera, uma coisa por vez, por prioridade
/// (reunião chegando > gravação > aviso rápido > foco/timer > mic mudo). Some quando não há nada.
/// Em Macs sem notch, aparece como uma pílula no topo da tela (desligado por padrão).
@MainActor
final class NotchCenter: ObservableObject {
    static let shared = NotchCenter()
    static let key = "notchOn"

    /// O que pode aparecer; cada um tem seu interruptor em Ajustes → Notch
    enum Kind: String, CaseIterable, Identifiable {
        case meeting, recording, flash, agents, focus, timer, mic
        var id: String { rawValue }
        var key: String { "notch.\(rawValue)" }
        /// A gravação vem desligada: discreta, para quem compartilha a tela (aparece no painel ao passar o mouse)
        @MainActor var isOn: Bool { UserDefaults.standard.object(forKey: key) == nil ? self != .recording : UserDefaults.standard.bool(forKey: key) }
    }

    /// Minutos antes da reunião em que o aviso aparece
    static let leadKey = "notch.meetingLead"
    static var meetingLead: TimeInterval {
        let m = UserDefaults.standard.integer(forKey: leadKey)
        return TimeInterval([1, 2, 5].contains(m) ? m : 2) * 60
    }

    enum Activity: Equatable {
        case meeting(title: String, start: Date, hasLink: Bool)
        case recording(since: Date)
        case flash(icon: String, color: Color, text: String)
        case focus(end: Date, rest: Bool)
        case timer(label: String, end: Date)
        case micMuted
        /// Agentes de IA: quantos trabalham e quantos esperam você
        case agents(working: Int, waiting: Int)
    }

    @Published private(set) var activity: Activity?
    private var flash: (Activity, Date?)?
    /// Um teste de Ajustes → Notch fica na tela até esta hora, mesmo com o aviso desligado
    private var testUntil: Date?
    private var panel: NSPanel?
    private var timer: Timer?
    private var muted = false
    /// Algum app usando o microfone (numa chamada): o aviso de reunião some depois do início
    private var micBusy = false
    /// Desde quando algum app está usando o microfone (uma chamada): o painel do notch mostra o tempo
    private(set) var callSince: Date?
    private var lastMuteCheck = Date.distantPast

    /// Ligado por padrão só em Macs com notch
    var isOn: Bool { UserDefaults.standard.object(forKey: Self.key) as? Bool ?? Self.hasNotch }

    static var hasNotch: Bool { (NSScreen.screens.first?.safeAreaInsets.top ?? 0) > 0 }

    /// A tela com notch (a embutida); sem notch, a principal
    private static var screen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main }

    func refresh() {
        timer?.invalidate()
        timer = nil
        NotchHover.shared.refresh()
        guard isOn else { activity = nil; panel?.orderOut(nil); return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { NotchCenter.shared.update() }
        }
        update()
    }

    /// Avisos do Menew ("Copiado", "Pensando…"): no notch, quando ele está ligado
    func show(icon: String, color: Color, text: String, duration: TimeInterval?) -> Bool {
        guard isOn, Kind.flash.isOn else { return false }
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
        if let testUntil, testUntil > now { place(); return }
        testUntil = nil
        if let (_, until) = flash, let until, until < now { flash = nil }
        if now.timeIntervalSince(lastMuteCheck) > 2 {
            lastMuteCheck = now
            // Só importa numa chamada: mic mudo com algum app usando o microfone
            micBusy = AudioControl.micInUse()
            callSince = micBusy ? (callSince ?? now) : nil
            muted = AudioControl.isMuted(input: true) && micBusy
        }
        let next = Self.pick(now: now, flash: flash?.0, muted: muted, inCall: micBusy)
        if next != activity {
            withAnimation(.spring(duration: 0.35)) { activity = next }
        }
        place()
    }

    /// A ordem de importância
    static func pick(now: Date, flash: Activity?, muted: Bool, inCall: Bool = false) -> Activity? {
        if Kind.meeting.isOn, let m = MeetingStore.shared.next, !MeetingStore.shared.notchIgnores(m),
           showsMeeting(m, now: now, inCall: inCall, joined: MeetingStore.shared.joinedID == m.id) {
            return .meeting(title: m.title, start: m.start, hasLink: m.link != nil)
        }
        if Kind.recording.isOn, ScreenRecorder.shared.isRecording { return .recording(since: ScreenRecorder.shared.started) }
        if Kind.recording.isOn, RecordingStore.shared.isRecording { return .recording(since: RecordingStore.shared.startedAt) }
        // Filtro de Foco "só reuniões": o resto espera o Foco acabar
        if FocusFilterState.shared.quietNotch { return nil }
        if Kind.flash.isOn, let flash { return flash }
        let hub = AgentHub.shared
        if Kind.agents.isOn, hub.waiting > 0 { return .agents(working: hub.working, waiting: hub.waiting) }
        let focus = FocusTimer.shared
        if Kind.focus.isOn, focus.isRunning { return .focus(end: focus.endsAt, rest: focus.phase == .rest) }
        if Kind.timer.isOn, let t = TimerStore.shared.active.min(by: { $0.end < $1.end }) { return .timer(label: t.label, end: t.end) }
        if Kind.agents.isOn, hub.working > 0 { return .agents(working: hub.working, waiting: 0) }
        if Kind.mic.isOn, muted { return .micMuted }
        return nil
    }

    /// O aviso aparece até `meetingLead` antes. Some quando você entra (botão Entrar ou microfone em uso depois
    /// do início) e, de qualquer jeito, 1 minuto depois de começar
    static func showsMeeting(_ m: Meeting, now: Date, inCall: Bool, joined: Bool) -> Bool {
        guard m.start.timeIntervalSince(now) <= meetingLead, !joined else { return false }
        if m.start <= now { return !inCall && now.timeIntervalSince(m.start) < 60 }
        return true
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
        case .agents(_, let waiting):
            Image(systemName: waiting > 0 ? "hand.raised.fill" : "sparkles").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(waiting > 0 ? .orange : .purple)
                .symbolEffect(.pulse, isActive: waiting == 0)
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
        case .agents(let working, let waiting):
            Text(waiting > 0 ? L("%d espera você", waiting) : (working == 1 ? L("1 trabalhando") : L("%d trabalhando", working)))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(waiting > 0 ? .orange : .white).lineLimit(1)
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
            Button { if RecordingStore.shared.isRecording { RecordingStore.shared.stop() } else { ScreenRecorder.shared.stop() } } label: {
                Label(L("Parar"), systemImage: "stop.fill").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain).padding(.bottom, 8)
        case .agents(_, let waiting) where waiting > 0:
            // Quem espera, com um botão que traz o terminal dele para a frente
            if let s = AgentHub.shared.sessions.first(where: { $0.state == .waiting }) {
                HStack(spacing: 10) {
                    Text("\(s.agent.short) · \(s.project)").font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 6)
                    Button { AgentHub.shared.focus(s) } label: {
                        Label(L("Abrir"), systemImage: "terminal.fill").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Color.orange.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
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

extension NotchCenter.Kind {
    var icon: String {
        switch self {
        case .meeting: "video.fill"
        case .recording: "record.circle"
        case .flash: "checkmark.circle.fill"
        case .focus: "scope"
        case .timer: "hourglass"
        case .mic: "mic.slash.fill"
        case .agents: "sparkles"
        }
    }

    var title: String {
        switch self {
        case .meeting: L("Reunião chegando")
        case .recording: L("Gravação de tela")
        case .flash: L("Avisos do Menew")
        case .focus: L("Foco e pausa")
        case .timer: L("Timers")
        case .mic: L("Mic mudo numa chamada")
        case .agents: L("Agentes de IA")
        }
    }

    var detail: String {
        switch self {
        case .meeting: L("Com o botão Entrar quando a reunião tem link.")
        case .recording: L("O tempo gravado e o botão Parar. Desligado, só um símbolo de parar na barra de menus; ao passar o mouse no notch, o tempo aparece.")
        case .flash: L("“Copiado”, volume, brilho e outros. Desligado, aparecem no meio da tela.")
        case .focus: L("O tempo que falta da sessão de foco.")
        case .timer: L("A contagem do timer mais próximo.")
        case .mic: L("Só aparece quando algum app está usando o microfone.")
        case .agents: L("Quantos agentes trabalham e quem espera você, com um botão para abrir o terminal. Precisa dos avisos ligados em Agentes de IA.")
        }
    }

    /// Exemplo para a prévia e o botão Testar
    var demo: NotchCenter.Activity {
        switch self {
        case .meeting: .meeting(title: L("Alinhamento semanal"), start: Date().addingTimeInterval(95), hasLink: true)
        case .recording: .recording(since: Date().addingTimeInterval(-42))
        case .flash: .flash(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
        case .focus: .focus(end: Date().addingTimeInterval(18 * 60), rest: false)
        case .timer: .timer(label: L("Chá"), end: Date().addingTimeInterval(4 * 60 + 12))
        case .mic: .micMuted
        case .agents: .agents(working: 2, waiting: 1)
        }
    }
}

extension NotchCenter {
    /// Mostra um exemplo no notch de verdade por alguns segundos
    func test(_ kind: Kind) {
        testUntil = Date().addingTimeInterval(4)
        withAnimation(.spring(duration: 0.35)) { activity = kind.demo }
        place()
        // Com o notch desligado não há timer: limpa sozinho
        if !isOn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.1) { [weak self] in
                guard let self, !self.isOn else { return }
                self.testUntil = nil; self.activity = nil; self.panel?.orderOut(nil)
            }
        }
    }
}

/// Ajustes → Notch: o interruptor geral, a prévia e um interruptor por aviso
struct NotchSettingsSection: View {
    @State private var on = NotchCenter.shared.isOn
    @State private var hover = NotchHover.hoverOn
    @State private var drop = NotchHover.dropOn
    @State private var kinds: [NotchCenter.Kind: Bool] = Dictionary(uniqueKeysWithValues: NotchCenter.Kind.allCases.map { ($0, $0.isOn) })
    @AppStorage(NotchCenter.leadKey) private var lead = 2
    @State private var onlyReal = MeetingStore.onlyReal
    @State private var muted = MeetingStore.mutedTitles
    @StateObject private var preview = NotchCenter()
    @State private var step = 0
    private let tick = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSection(title: L("Prévia"), footer: NotchCenter.hasNotch
                         ? L("Uma coisa por vez, a mais importante primeiro. Sem nada acontecendo, o notch fica como sempre.")
                         : L("Este Mac não tem notch: os avisos aparecem como uma pílula no topo da tela.")) {
                ZStack(alignment: .top) {
                    LinearGradient(colors: [Color(red: 0.42, green: 0.45, blue: 0.62), Color(red: 0.55, green: 0.5, blue: 0.68)], startPoint: .leading, endPoint: .trailing)
                    NotchView(center: preview, notch: CGSize(width: 200, height: 37)).frame(width: 440, height: 75)
                }
                .frame(height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(10)
            }
            GlassSection(title: L("Notch")) {
                ToggleRow(title: NotchCenter.hasNotch ? L("Avisos ao vivo no notch") : L("Avisos ao vivo no topo da tela"),
                          detail: L("Reunião chegando, gravação, foco, timers, mic mudo e os avisos do Menew aparecem ao lado da câmera."),
                          isOn: Binding(get: { on }, set: { on = $0; UserDefaults.standard.set($0, forKey: NotchCenter.key); NotchCenter.shared.refresh() }))
            }
            if NotchCenter.hasNotch {
                GlassSection(title: L("Painel do notch")) {
                    ToggleRow(title: L("Abrir ao passar o mouse"),
                              detail: L("Pare o mouse no notch: aparecem a próxima reunião, o timer e atalhos (microfone, captura, memória, clipboard, estante). Numa chamada, gravar com ata e legendas."),
                              isOn: Binding(get: { hover }, set: { hover = $0; UserDefaults.standard.set($0, forKey: NotchHover.hoverKey); NotchHover.shared.refresh() }))
                    RowDivider()
                    ToggleRow(title: L("Soltar arquivos no notch"),
                              detail: L("Arraste arquivos até o notch e solte: eles vão para a estante."),
                              isOn: Binding(get: { drop }, set: { drop = $0; UserDefaults.standard.set($0, forKey: NotchHover.dropKey); NotchHover.shared.refresh() }))
                }
                .disabled(!on).opacity(on ? 1 : 0.5)
            }
            GlassSection(title: L("O que aparece"), footer: L("Na ordem de importância: se duas coisas acontecem juntas, aparece a de cima.")) {
                ForEach(Array(NotchCenter.Kind.allCases.enumerated()), id: \.element) { i, k in
                    if i > 0 { RowDivider() }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: k.icon).font(.system(size: 12, weight: .medium)).foregroundStyle(.orange).frame(width: 18).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k.title).font(.system(size: 13))
                            Text(k.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if k == .meeting {
                                Picker("", selection: $lead) {
                                    ForEach([1, 2, 5], id: \.self) { Text(L("%@ min antes", "\($0)")).tag($0) }
                                }
                                .labelsHidden().pickerStyle(.menu).fixedSize().padding(.top, 2)
                                Toggle(L("Só reuniões com link ou outras pessoas"), isOn: Binding(get: { onlyReal }, set: {
                                    onlyReal = $0; UserDefaults.standard.set($0, forKey: MeetingStore.onlyRealKey); NotchCenter.shared.update()
                                }))
                                .toggleStyle(.checkbox).font(.system(size: 11.5))
                                .help(L("Sem link nem convidados, o evento é um bloqueio na agenda (almoço, ginástica, foco) e não avisa."))
                                if !muted.isEmpty {
                                    Text(L("Nunca avisar de:")).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 2)
                                    FlowLayout(spacing: 6) {
                                        ForEach(muted, id: \.self) { t in
                                            Button {
                                                muted.removeAll { $0 == t }; MeetingStore.mutedTitles = muted; NotchCenter.shared.update()
                                            } label: {
                                                HStack(spacing: 4) { Text(t); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                                    .font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 3)
                                                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                                            }
                                            .buttonStyle(.plain).help(L("Voltar a avisar de “%@”", t))
                                        }
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 8)
                        Button(L("Testar")) { NotchCenter.shared.test(k) }
                            .buttonStyle(.borderless).font(.system(size: 11.5))
                        Toggle("", isOn: Binding(get: { kinds[k] ?? true }, set: { kinds[k] = $0; UserDefaults.standard.set($0, forKey: k.key); NotchCenter.shared.update() }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .onAppear { show() }
        .onReceive(tick) { _ in step += 1; show() }
    }

    /// A prévia passa pelos avisos ligados, um de cada vez
    private func show() {
        let list = NotchCenter.Kind.allCases.filter { kinds[$0] ?? true }
        guard !list.isEmpty else { preview.showDemo(.flash(icon: "moon.zzz.fill", color: .gray, text: L("Nada ligado"))); return }
        withAnimation(.spring(duration: 0.35)) { preview.showDemo(list[step % list.count].demo) }
    }
}
