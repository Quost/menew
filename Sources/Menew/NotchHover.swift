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
        // Cada agente ativo ganha uma linha, e o uso de hoje, outra
        let agentsH: CGFloat = model.agents.isEmpty ? 0 : CGFloat(model.agents.count) * 40 + 30
        let size = m == .hover ? NSSize(width: 480, height: (model.after != nil ? 172 : 150) + agentsH) : NSSize(width: 360, height: 110)
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
    /// Agentes de IA trabalhando, esperando você ou que terminaram há pouco (até 3)
    @Published var agents: [AgentSession] = []
    @Published var usageLine: String?

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
        agents = Array(AgentHub.shared.active(now: now).prefix(3))
        usageLine = agents.isEmpty ? nil : Self.usage()
    }

    /// "Hoje 9,3 mi tokens · ~US$ 5,80 · Claude 5 h 62% · Codex 5 h 21%"
    static func usage() -> String {
        let u = AgentUsageStore.shared
        let t = u.totals(since: Calendar.current.startOfDay(for: Date()))
        var parts = [L("Hoje %@ tokens", AgentsView.tokens(t.tokens))]
        if t.cost > 0 { parts.append("~" + AgentsView.money(t.cost)) }
        for a in AgentKind.allCases {
            if let w = u.limits[a]?.first { parts.append("\(a.short) \(w.label) \(Int(w.usedPercent.rounded()))%") }
        }
        return parts.joined(separator: " · ")
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

    // Agentes de IA: o que cada um está fazendo agora
    private var agentsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.agents) { s in
                Button { NotchHover.run { AgentHub.shared.focus(s) } } label: {
                    HStack(spacing: 9) {
                        Image(systemName: s.agent.icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(s.agent.color.gradient))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(s.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Circle().fill(s.state == .waiting ? Color.orange : s.state == .working ? .blue : .green).frame(width: 6, height: 6)
                                Text(s.stateTitle).font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(s.state == .waiting ? Color.orange : .white.opacity(0.6))
                            }
                            Text(s.state == .waiting ? (s.message ?? s.step ?? "") : (s.step ?? s.task ?? s.agent.name))
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 6)
                        if s.state == .working, let t = s.turnStart {
                            Text(t, style: .timer).font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                        }
                        Image(systemName: "terminal.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                            .frame(width: 26, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.12)))
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(s.task ?? s.project)
            }
            if let u = model.usageLine {
                Button { NotchHover.run { MenewWindow.shared.show(.agents) } } label: {
                    Label(u, systemImage: "chart.bar.fill").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                .buttonStyle(.plain)
                .help(L("Abrir Agentes de IA"))
            }
        }
    }

    // Passando o mouse: o que vem agora e atalhos
    private var hover: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.agents.isEmpty { agentsBlock }
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
