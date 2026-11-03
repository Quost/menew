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
        let size = m == .hover ? NSSize(width: 460, height: 150) : NSSize(width: 360, height: 110)
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

    func refresh() {
        meeting = MeetingStore.shared.next
        timers = Array(TimerStore.shared.active.prefix(2))
        focusEnd = FocusTimer.shared.isRunning ? FocusTimer.shared.endsAt : nil
        micMuted = AudioControl.isMuted(input: true)
        recordingSince = RecordingStore.shared.isRecording ? RecordingStore.shared.startedAt : nil
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

    // Passando o mouse: o que vem agora e atalhos
    private var hover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let m = model.meeting {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Text(m.start > Date() ? L("às %@", m.start.formatted(date: .omitted, time: .shortened)) : L("agora"))
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                        }
                        if m.link != nil {
                            Button { NotchHover.run { MeetingStore.shared.join() } } label: {
                                Text(L("Entrar")).font(.system(size: 11.5, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor))
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
                button("camera.viewfinder", L("Capturar"), .pink) { NotchHover.run { ScreenCapture.area() } }
                button("doc.on.clipboard", L("Clipboard"), .purple) { NotchHover.run { app?.clipPanel.show() } }
                button("tray.full.fill", L("Estante"), Theme.indigo) { NotchHover.run { app?.shelf.toggle() } }
                button("command", L("Paleta"), .blue) { NotchHover.run { app?.palette.show() } }
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
