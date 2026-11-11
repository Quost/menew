import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Notch, fase 2: passe o mouse no notch e ele abre um painel com a próxima reunião, os timers e atalhos;
/// arraste arquivos até ele e solte para guardar na estante. Só em Macs com notch.
@MainActor
final class NotchHover: NSObject {
    static let shared = NotchHover()
    static let hoverKey = "notch.hover"
    static let dropKey = "notch.drop"

    enum Mode { case hover, drop }

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var dwell: DispatchWorkItem?
    private(set) var mode: Mode?
    private var dragCount = NSPasteboard(name: .drag).changeCount
    private let model = NotchHoverModel()

    static var hoverOn: Bool { UserDefaults.standard.object(forKey: hoverKey) as? Bool ?? true }
    static var dropOn: Bool { UserDefaults.standard.object(forKey: dropKey) as? Bool ?? true }

    func refresh() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        close()
        guard NotchCenter.hasNotch, NotchCenter.shared.isOn, Self.hoverOn || Self.dropOn else { return }
        let types: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: types, handler: { e in
            let t = e.type
            MainActor.assumeIsolated { NotchHover.shared.handle(t) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: types, handler: { e in
            NotchHover.shared.handle(e.type)
            return e
        }) { monitors.append(l) }
    }

    /// A área do notch na tela embutida, com uma folga para o mouse achar fácil
    private static func notchRect(margin: CGFloat) -> NSRect? {
        guard let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { return nil }
        let n = NotchCenter.notchSize(s)
        return NSRect(x: s.frame.midX - n.width / 2 - margin, y: s.frame.maxY - n.height - margin, width: n.width + margin * 2, height: n.height + margin)
    }

    private func handle(_ type: NSEvent.EventType) {
        let p = NSEvent.mouseLocation
        switch type {
        case .leftMouseDragged:
            guard Self.dropOn else { return }
            // Só quando o arrasto carrega arquivos (não ao mover janelas ou selecionar texto)
            let pb = NSPasteboard(name: .drag)
            guard pb.changeCount != dragCount || mode == .drop,
                  pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
            if let r = Self.notchRect(margin: 60), r.contains(p) {
                if mode != .drop { open(.drop) }
            } else if mode == .drop, let f = panel?.frame.insetBy(dx: -40, dy: -40), !f.contains(p) {
                close()
            }
        case .leftMouseUp:
            dragCount = NSPasteboard(name: .drag).changeCount
            // Depois de soltar, o painel de soltar some sozinho
            if mode == .drop { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in if self?.mode == .drop { self?.close() } } }
        default:
            guard Self.hoverOn, NSEvent.pressedMouseButtons == 0 else { return }
            if mode == .hover {
                if let f = panel?.frame.insetBy(dx: -12, dy: -12), !f.contains(p) { close() }
            } else if mode == nil, let r = Self.notchRect(margin: 4), r.contains(p) {
                // Um instante parado em cima, para não abrir quando o mouse só passa a caminho do menu
                guard dwell == nil else { return }
                let w = DispatchWorkItem { [weak self] in
                    self?.dwell = nil
                    if let r = Self.notchRect(margin: 4), r.contains(NSEvent.mouseLocation) { self?.open(.hover) }
                }
                dwell = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
            } else {
                dwell?.cancel()
                dwell = nil
            }
        }
    }

    func open(_ m: Mode) {
        guard let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { return }
        mode = m
        model.mode = m
        model.refresh()
        // A linha "depois:" da reunião seguinte pede um pouco mais de altura
        // Cada agente ativo ganha uma linha, e cada ferramenta com limite ou uso hoje, outra
        let size = m == .hover ? NSSize(width: model.agentsHeight > 0 ? 540 : 480, height: (model.after != nil ? 172 : 150) + model.agentsHeight)
                               : NSSize(width: 360, height: 110)
        let frame = NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height, width: size.width, height: size.height)
        let p = panel ?? makePanel()
        panel = p
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        withAnimation(.spring(duration: 0.3)) { model.shown = true }
    }

    func close() {
        dwell?.cancel()
        dwell = nil
        mode = nil
        model.shown = false
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Acima do aviso ao vivo, que fica um nível abaixo
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: NotchHoverView(model: model, notch: NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }).map(NotchCenter.notchSize) ?? .zero))
        return p
    }

    // MARK: Ações dos botões

    static func run(_ action: () -> Void) {
        shared.close()
        action()
    }
}

@MainActor
final class NotchHoverModel: ObservableObject {
    @Published var mode: NotchHover.Mode = .hover
    @Published var shown = false
    @Published var targeted = false
    @Published var meeting: Meeting?
    @Published var timers: [TimerStore.Countdown] = []
    @Published var focusEnd: Date?
    @Published var micMuted = false
    @Published var recordingSince: Date?
    /// Em chamada (algum app usando o microfone): desde quando
    @Published var callSince: Date?
    @Published var captionsOn = false
    /// A reunião depois da próxima, para planejar sem abrir o Calendário
    @Published var after: Meeting?
    /// Agentes de IA trabalhando, esperando você ou que terminaram há pouco (até 3), e quantos mais
    @Published var agents: [AgentSession] = []
    @Published var moreAgents = 0
    /// Uma linha por ferramenta: as janelas do plano e o uso de hoje
    @Published var limitRows: [AgentLimitRow] = []

    /// A altura que os agentes acrescentam ao painel
    var agentsHeight: CGFloat {
        guard !agents.isEmpty || !limitRows.isEmpty else { return 0 }
        return CGFloat(agents.count) * 42 + (moreAgents > 0 ? 18 : 0) + (limitRows.isEmpty ? 0 : CGFloat(limitRows.count) * 42 + 18) + 10
            + CGFloat(limitRows.filter { $0.forecast != nil }.count) * 18
    }

    func refresh() {
        let now = Date()
        meeting = MeetingStore.shared.next
        let from = max(meeting?.start ?? now, now)
        after = MeetingStore.shared.today.first { $0.start > from && $0.id != meeting?.id }
        callSince = AudioControl.micInUse() ? (NotchCenter.shared.callSince ?? callSince ?? now) : nil
        captionsOn = LiveCaptions.shared.running
        timers = Array(TimerStore.shared.active.prefix(2))
        focusEnd = FocusTimer.shared.isRunning ? FocusTimer.shared.endsAt : nil
        micMuted = AudioControl.isMuted(input: true)
        recordingSince = RecordingStore.shared.isRecording ? RecordingStore.shared.startedAt : nil
        let active = AgentHub.shared.active(now: now)
        agents = Array(active.prefix(3))
        moreAgents = max(0, active.count - 3)
        // Os limites e o uso de hoje ficam sempre, com ou sem sessão aberta
        limitRows = AgentLimitRow.current()
    }
}

struct NotchHoverView: View {
    @ObservedObject var model: NotchHoverModel
    let notch: CGSize
    private var app: AppDelegate? { NSApp.delegate as? AppDelegate }

    var body: some View {
        VStack(spacing: 0) {
            if model.shown {
                Group {
                    if model.mode == .drop { drop } else { hover }
                }
                .padding(.top, notch.height + 6).padding(.horizontal, 16).padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .foregroundStyle(.white)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22).fill(.black))
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Arrastando arquivos: a área de soltar
    private var drop: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 20, weight: .semibold))
                .foregroundStyle(model.targeted ? .green : .white.opacity(0.85))
            Text(L("Solte para guardar na estante")).font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(model.targeted ? .green : .white.opacity(0.35)))
        .onDrop(of: [.fileURL, .url, .image, .plainText], isTargeted: $model.targeted) { providers in
            let ok = ShelfStore.shared.accept(providers)
            if ok { NotchHover.run { app?.shelf.show(nearMouse: false) } }
            return ok
        }
    }

    // Agentes de IA: o que cada um está fazendo agora, e os limites
    private var agentsBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.agents) { s in agentRow(s) }
            if model.moreAgents > 0 {
                Button { NotchHover.run { MenewWindow.shared.show(.agents) } } label: {
                    Text(L("e mais %d", model.moreAgents)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain).padding(.leading, 34)
            }
            if !model.limitRows.isEmpty {
                VStack(spacing: 9) {
                    ForEach(model.limitRows) { r in limitRow(r) }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.07)))
                .contentShape(Rectangle())
                .onTapGesture { NotchHover.run { MenewWindow.shared.show(.agents) } }
                .help(L("Abrir Agentes de IA"))
                .padding(.top, 6)
            }
        }
    }

    private func agentRow(_ s: AgentSession) -> some View {
        Button { NotchHover.run { AgentHub.shared.focus(s) } } label: {
            HStack(spacing: 10) {
                NotchView.agentBadge(s.agent, state: s.state, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(s.project).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).layoutPriority(1)
                        if let t = s.task {
                            Text(t).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                        }
                    }
                    HStack(spacing: 5) {
                        switch s.state {
                        case .waiting:
                            Image(systemName: "hand.raised.fill").font(.system(size: 9.5))
                            Text(s.waitingText).lineLimit(1).truncationMode(.middle)
                        case .done:
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 9.5))
                            Text(s.lastDuration.map { L("Pronto em %@", AgentStep.duration($0)) } ?? L("Pronto")).lineLimit(1)
                        default:
                            Image(systemName: s.stepIcon).font(.system(size: 9.5))
                            Text(s.step ?? L("Pensando…")).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(s.state == .waiting ? Color.orange : s.state == .done ? Color.green.opacity(0.9) : .white.opacity(0.7))
                }
                Spacer(minLength: 8)
                if s.state == .working, let t = s.turnStart {
                    Text(t, style: .timer).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                }
                Image(systemName: "terminal.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                    .frame(width: 28, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(s.state == .waiting ? Color.orange.opacity(0.85) : .white.opacity(0.12)))
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(s.task ?? s.project)
    }

    /// Claude                                  601 mil hoje · US$ 0,41
    /// 5 h ▰▰▱ 62% · 10:55     Sem. ▰▱▱ 38% · sex.
    private func limitRow(_ r: AgentLimitRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: r.agent.icon).font(.system(size: 9, weight: .bold)).foregroundStyle(r.agent.color)
                Text(r.agent.name).font(.system(size: 11.5, weight: .semibold))
                Spacer(minLength: 8)
                Text(r.today).font(.system(size: 10.5, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.55)).fixedSize()
            }
            if r.windows.isEmpty {
                Text(L("sem limites lidos")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35)).padding(.leading, 15)
            } else {
                HStack(spacing: 18) {
                    ForEach(r.windows) { w in
                        HStack(spacing: 6) {
                            Text(w.short).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.55)).fixedSize()
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.14))
                                Capsule().fill(Self.limitColor(w.usedPercent, base: r.agent.color)).frame(width: max(3, 56 * min(1, w.usedPercent / 100)))
                            }
                            .frame(width: 56, height: 5)
                            Text("\(Int(w.usedPercent.rounded()))%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(w.usedPercent >= 90 ? Color.red : w.usedPercent >= 75 ? .orange : .white).fixedSize()
                            if let reset = w.resetsAt {
                                Text(Self.resetShort(reset)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize()
                            }
                        }
                        .help(w.resetsAt.map { L("%@: zera %@", w.label, $0.formatted(.relative(presentation: .named).locale(L10n.locale))) } ?? w.label)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 15)
            }
            // No ritmo de agora: quando acaba, ou até onde chega no reset
            if let f = r.forecast {
                Label(f.text, systemImage: f.warn ? "exclamationmark.triangle.fill" : "speedometer")
                    .font(.system(size: 10.5, weight: f.warn ? .semibold : .regular))
                    .foregroundStyle(f.warn ? Color.orange : .white.opacity(0.45)).lineLimit(1).padding(.leading, 15)
            }
        }
    }

    static func limitColor(_ p: Double, base: Color) -> Color { p >= 90 ? .red : p >= 75 ? .orange : base }

    /// Hoje: "14:30"; esta semana: "sex."; mais longe: "12/11"
    static func resetShort(_ d: Date, now: Date = Date()) -> String {
        if d.timeIntervalSince(now) < 20 * 3600 { return d.formatted(.dateTime.hour().minute().locale(L10n.locale)) }
        if d.timeIntervalSince(now) < 6 * 86400 { return d.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale)) }
        return d.formatted(.dateTime.day().month(.defaultDigits).locale(L10n.locale))
    }

    // Passando o mouse: o que vem agora e atalhos
    private var hover: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.agents.isEmpty || !model.limitRows.isEmpty { agentsBlock }
            HStack(spacing: 12) {
                if let m = model.meeting {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Text(m.start > Date() ? L("às %@", m.start.formatted(date: .omitted, time: .shortened)) : L("agora"))
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                            if let a = model.after {
                                Text(L("depois: %@ às %@", a.title, a.start.formatted(date: .omitted, time: .shortened)))
                                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                            }
                        }
                        if m.link != nil {
                            Button { NotchHover.run { MeetingStore.shared.join() } } label: {
                                Text(L("Entrar")).font(.system(size: 11.5, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor))
                            }
                            .buttonStyle(.plain)
                        }
                        // Bloqueio de agenda (almoço, ginástica) ou aviso que atrapalha: some desta vez ou para sempre
                        Menu {
                            Button(L("Dispensar este aviso")) { NotchHover.run { MeetingStore.shared.dismiss(m) } }
                            Button(L("Nunca avisar de “%@”", m.title)) { NotchHover.run { MeetingStore.shared.mute(m.title) } }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                                .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.12)))
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help(L("Dispensar o aviso"))
                    }
                } else if model.callSince != nil {
                    Label(L("Em chamada"), systemImage: "phone.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.green)
                } else {
                    Label(L("Sem reuniões chegando"), systemImage: "calendar").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 4)
                if let since = model.recordingSince {
                    Button { NotchHover.run { RecordingStore.shared.stop() } } label: {
                        HStack(spacing: 5) {
                            Circle().fill(.red).frame(width: 7, height: 7)
                            Text(since, style: .timer).monospacedDigit()
                            Image(systemName: "stop.fill").font(.system(size: 9))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help(L("Parar a gravação"))
                } else if let since = model.callSince {
                    // O telefone já está à esquerda quando não há reunião; com reunião, ele diz que é chamada
                    Label { Text(since, style: .timer).monospacedDigit() } icon: {
                        if model.meeting != nil { Image(systemName: "phone.fill").foregroundStyle(.green) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .help(L("Tempo em chamada"))
                } else if let end = model.focusEnd {
                    Label { Text(end, style: .timer).monospacedDigit() } icon: { Image(systemName: "scope").foregroundStyle(.orange) }
                        .font(.system(size: 12, weight: .semibold))
                } else if let t = model.timers.first {
                    Label { Text(t.end, style: .timer).monospacedDigit() } icon: { Image(systemName: "hourglass").foregroundStyle(.blue) }
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            HStack(spacing: 8) {
                button(model.micMuted ? "mic.slash.fill" : "mic.fill", model.micMuted ? L("Mudo") : L("Microfone"), model.micMuted ? .red : .white) {
                    _ = app?.toolbox.toggleMic()
                    model.micMuted = AudioControl.isMuted(input: true)
                }
                if model.callSince != nil {
                    // Numa chamada: o que serve agora (gravar com ata, legendas) vem na frente
                    if model.recordingSince != nil {
                        button("stop.fill", L("Parar"), .red) { NotchHover.run { RecordingStore.shared.stop() } }
                    } else {
                        button("waveform.badge.mic", L("Gravar ata"), .red) { NotchHover.run { RecordingStore.shared.start(source: .both) } }
                    }
                    button("captions.bubble.fill", L("Legendas"), model.captionsOn ? .green : .teal) {
                        LiveCaptions.shared.toggle()
                        model.captionsOn = LiveCaptions.shared.running
                    }
                    button("camera.viewfinder", L("Capturar"), .pink) { NotchHover.run { ScreenCapture.area() } }
                    button("brain.head.profile", L("Memória"), .pink) { NotchHover.run { MemoryStore.shared.capture() } }
                } else {
                    button("camera.viewfinder", L("Capturar"), .pink) { NotchHover.run { ScreenCapture.area() } }
                    button("brain.head.profile", L("Memória"), .pink) { NotchHover.run { MemoryStore.shared.capture() } }
                    button("doc.on.clipboard", L("Clipboard"), .purple) { NotchHover.run { app?.clipPanel.show() } }
                    button("tray.full.fill", L("Estante"), Theme.indigo) { NotchHover.run { app?.shelf.toggle() } }
                }
            }
        }
    }

    private func button(_ icon: String, _ title: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color).frame(height: 18)
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

private func reach(_ p: LimitProjection) -> Double { if case .reaches(let v) = p.kind { return v }; return 100 }

/// Uma linha do painel: as janelas do plano de uma ferramenta e quanto ela usou hoje
struct AgentLimitRow: Identifiable, Equatable {
    var id: String { agent.rawValue }
    let agent: AgentKind
    let windows: [RateWindow]
    let today: String
    /// A janela mais apertada no ritmo de agora: "5 h: acaba às 14:10" (aviso) ou "5 h: chega a ~48% até zerar"
    var forecast: (text: String, warn: Bool)?

    static func == (a: AgentLimitRow, b: AgentLimitRow) -> Bool { a.agent == b.agent && a.windows == b.windows && a.today == b.today && a.forecast?.text == b.forecast?.text }

    @MainActor static func current() -> [AgentLimitRow] {
        let u = AgentUsageStore.shared
        let start = Calendar.current.startOfDay(for: Date())
        return AgentKind.allCases.compactMap { a in
            let t = u.totals(since: start, agent: a)
            let windows = Array(u.current(a).prefix(3))
            guard !windows.isEmpty || t.tokens > 0 || t.credits > 0 else { return nil }
            // O Kiro conta em créditos (e alguns pedidos dele nem têm tokens)
            var today = t.tokens > 0 ? L("%@ hoje", AgentsView.tokens(t.tokens)) : L("%@ créditos hoje", String(format: "%.1f", t.credits))
            if t.tokens > 0, t.credits > 0 { today += " · " + L("%@ créditos", String(format: "%.1f", t.credits)) }
            if t.cost >= 0.01 { today += " · " + AgentsView.money(t.cost) }
            // A que acaba primeiro; sem nenhuma acabando, a que mais se aproxima de 100% no reset
            let projections = windows.compactMap { w in u.projection(a, w).map { (w, $0) } }
            var forecast: (String, Bool)?
            if let (w, p) = projections.filter({ $0.1.runsOut != nil }).min(by: { $0.1.runsOut! < $1.1.runsOut! }) {
                forecast = ("\(w.short): \(p.text)", true)
            } else if let (w, p) = projections.max(by: { reach($0.1) < reach($1.1) }), reach(p) >= 50 {
                forecast = ("\(w.short): \(p.text)", false)
            }
            return AgentLimitRow(agent: a, windows: windows, today: today, forecast: forecast)
        }
    }
}
