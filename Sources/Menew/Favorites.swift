import SwiftUI

/// Favoritos no topo da aba Ações: os atalhos que você mais usa, num toque. Você escolhe quais e em que ordem.
/// Cada um chama a mesma função do botão que já existe mais abaixo.
enum FavoriteAction: String, CaseIterable, Identifiable {
    case mic, sound, dark, awake, present, dock, desktop, hiddenFiles, capture, ocr, qr, color, plain, lock, eject, trash, focus, timer, cleaner, record, gif, scroll, uninstall, screenAsk
    var id: String { rawValue }

    static let key = "actionFavorites"
    static let defaults: [FavoriteAction] = [.mic, .awake, .dark, .capture, .present, .dock, .ocr, .color]

    var icon: String {
        switch self {
        case .mic: "mic.fill"
        case .sound: "speaker.wave.2.fill"
        case .dark: "moon.fill"
        case .awake: "cup.and.saucer.fill"
        case .present: "play.rectangle.fill"
        case .dock: "dock.rectangle"
        case .desktop: "menubar.dock.rectangle"
        case .hiddenFiles: "eye.fill"
        case .capture: "camera.viewfinder"
        case .ocr: "text.viewfinder"
        case .qr: "qrcode.viewfinder"
        case .color: "eyedropper.halffull"
        case .plain: "textformat"
        case .lock: "lock.fill"
        case .eject: "eject.fill"
        case .trash: "trash"
        case .focus: "timer"
        case .timer: "hourglass"
        case .cleaner: "sparkles"
        case .record: "record.circle"
        case .gif: "photo.stack"
        case .scroll: "arrow.down.doc"
        case .uninstall: "trash.square"
        case .screenAsk: "text.bubble"
        }
    }

    var color: Color {
        switch self {
        case .mic: .red
        case .sound: .pink
        case .dark: .indigo
        case .awake: .orange
        case .present: .green
        case .dock: .gray
        case .desktop: .teal
        case .hiddenFiles: .blue
        case .capture: .pink
        case .ocr: .green
        case .qr: .indigo
        case .color: Theme.violet
        case .plain: .brown
        case .lock: .gray
        case .eject: .mint
        case .trash: .red
        case .focus: .red
        case .timer: .orange
        case .cleaner: .blue
        case .record: .red
        case .gif: .orange
        case .scroll: .blue
        case .uninstall: .red
        case .screenAsk: .pink
        }
    }

    var title: String {
        switch self {
        case .mic: L("Mutar mic")
        case .sound: L("Mutar som")
        case .dark: L("Modo escuro")
        case .awake: L("Acordado")
        case .present: L("Apresentar")
        case .dock: L("Ocultar Dock")
        case .desktop: L("Ícones da mesa")
        case .hiddenFiles: L("Arquivos ocultos")
        case .capture: L("Capturar")
        case .ocr: L("Texto da tela")
        case .qr: L("Ler QR")
        case .color: L("Conta-gotas")
        case .plain: L("Texto puro")
        case .lock: L("Bloquear")
        case .eject: L("Ejetar")
        case .trash: L("Lixeira")
        case .focus: L("Foco 25 min")
        case .timer: L("Timer 10 min")
        case .cleaner: L("Liberar espaço")
        case .record: L("Gravar tela")
        case .gif: L("Gravar GIF")
        case .scroll: L("Captura com rolagem")
        case .uninstall: L("Desinstalar app")
        case .screenAsk: L("Perguntar à tela")
        }
    }

    /// Ligado agora (para os que ligam e desligam)
    @MainActor func isOn(_ tb: Toolbox) -> Bool? {
        switch self {
        case .mic: tb.micMuted
        case .sound: tb.soundMuted
        case .dark: tb.darkMode
        case .awake: tb.keepAwake
        case .present: PresentationMode.shared.isOn
        case .dock: tb.dockAutohide
        case .desktop: tb.desktopIconsHidden
        case .hiddenFiles: tb.hiddenFiles
        default: nil
        }
    }

    @MainActor func state(_ tb: Toolbox) -> String? {
        if let on = isOn(tb) { return on ? L("Ligado") : L("Desligado") }
        switch self {
        case .capture: return "⌃⌥⌘S"
        case .ocr: return "⌃⌥⌘T"
        case .eject: return tb.ejectableCount == 0 ? L("nenhum") : "\(tb.ejectableCount)"
        default: return nil
        }
    }

    @MainActor func run(_ tb: Toolbox, clipboard: ClipboardManager, openCleaner: () -> Void) {
        switch self {
        case .mic: _ = tb.toggleMic()
        case .sound: tb.toggleSound()
        case .dark: tb.toggleDarkMode()
        case .awake: tb.setKeepAwake(!tb.keepAwake)
        case .present: PresentationMode.shared.toggle()
        case .dock: tb.toggleDockAutohide()
        case .desktop: tb.toggleDesktopIcons()
        case .hiddenFiles: tb.toggleHiddenFiles()
        case .capture: ScreenCapture.area()
        case .ocr: TextRecognizer.captureScreenText()
        case .qr: QRCode.scanScreen()
        case .color: tb.pickColor(clipboard: clipboard)
        case .plain: tb.plainTextClipboard()
        case .lock: tb.lockScreen()
        case .eject: tb.ejectAll()
        case .trash: tb.emptyTrash()
        case .focus: FocusTimer.shared.start(minutes: 25)
        case .timer: TimerStore.shared.add(label: "", end: Date().addingTimeInterval(600), isAlarm: false)
        case .cleaner: openCleaner()
        case .record: ScreenRecorder.shared.start(gif: false)
        case .gif: ScreenRecorder.shared.start(gif: true)
        case .scroll: ScrollCapture.start()
        case .uninstall: Uninstaller.show()
        case .screenAsk: ScreenAsk.shared.start()
        }
    }

    static var saved: [FavoriteAction] {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key) else { return defaults }
            return raw.split(separator: ",").compactMap { FavoriteAction(rawValue: String($0)) }
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).joined(separator: ","), forKey: key) }
    }
}

/// Grade de favoritos com "Editar": tira com o –, põe com o +
struct FavoritesSection: View {
    @ObservedObject var tb: Toolbox
    @ObservedObject var presentation = PresentationMode.shared
    let clipboard: ClipboardManager
    var openCleaner: () -> Void
    @State private var favorites = FavoriteAction.saved
    @State private var editing = false
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Favoritos")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                Spacer()
                Button(editing ? L("Concluir") : L("Editar")) { withAnimation(.snappy) { editing.toggle() } }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.accentColor)
            }
            GlassGroup {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(favorites) { f in
                        let on = f.isOn(tb) ?? false
                        ActionTile(icon: f.icon, color: f.color, title: f.title, subtitle: f.state(tb), on: on) {
                            if editing {
                                withAnimation(.snappy) { favorites.removeAll { $0 == f } }
                                FavoriteAction.saved = favorites
                            } else {
                                f.run(tb, clipboard: clipboard, openCleaner: openCleaner)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if editing {
                                Image(systemName: "minus.circle.fill").font(.system(size: 15)).foregroundStyle(.white, .gray)
                                    .offset(x: -3, y: -3).allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
            if editing {
                let rest = FavoriteAction.allCases.filter { !favorites.contains($0) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Toque para adicionar aos favoritos")).font(.system(size: 11)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(rest) { f in
                            Button {
                                withAnimation(.snappy) { favorites.append(f) }
                                FavoriteAction.saved = favorites
                            } label: {
                                Label(f.title, systemImage: "plus").font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }
}
