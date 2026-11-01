import AppKit
import SwiftUI

/// Categorias da janela de Ajustes, na ordem da barra lateral
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, menubar, clipboard, shortcuts, calendar, alerts, links, privacy, backup, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("Geral")
        case .menubar: L("Barra de menus")
        case .clipboard: L("Clipboard")
        case .shortcuts: L("Atalhos e ações")
        case .calendar: L("Calendário e relógios")
        case .alerts: L("Alertas")
        case .links: L("Links rápidos")
        case .privacy: L("Privacidade")
        case .backup: L("Backup")
        case .about: L("Sobre e ajuda")
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .menubar: "menubar.rectangle"
        case .clipboard: "doc.on.clipboard.fill"
        case .shortcuts: "command"
        case .calendar: "calendar"
        case .alerts: "bell.badge.fill"
        case .links: "link"
        case .privacy: "hand.raised.fill"
        case .backup: "externaldrive.fill"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .menubar: .indigo
        case .clipboard: .purple
        case .shortcuts: .blue
        case .calendar: .red
        case .alerts: .orange
        case .links: .teal
        case .privacy: .green
        case .backup: .brown
        case .about: Theme.violet
        }
    }

    /// O que a busca encontra em cada categoria: os nomes dos ajustes dela (no idioma do app)
    var keywords: String {
        let words: [String] = switch self {
        case .general: [L("Aparência"), L("Tema"), L("Idioma"), L("Módulos"), L("Clipboard"), L("Ações"), L("Notas")]
        case .menubar: [L("Barra de menus"), L("Abrir ao iniciar o Mac"), "CPU", "RAM"]
        case .clipboard: [L("Colar automaticamente ao escolher"), L("Expandir abreviações dos snippets ao digitar"), L("Pausar captura"),
                          L("Ignorar senhas (1Password, Keychain…)"), L("Buscar texto dentro das imagens"), L("Apagar itens com mais de"),
                          L("Ignorar apps"), L("Limpar histórico (mantém fixados)")]
        case .shortcuts: [L("Histórico do clipboard"), L("Abrir este menu"), L("Paleta de comandos"), L("Mutar microfone"), L("Copiar texto da tela"),
                          L("Capturar tela"), L("Abrir a estante ao chacoalhar arquivos"), L("Organizar janelas com ⌃⌥"), L("Encaixar janelas arrastando"), L("Brilho de monitores externos")]
        case .calendar: [L("Calendário"), L("Mostrar a próxima reunião"), L("Horário de trabalho"), L("Avisar 1 minuto antes"), L("Relógios"), L("Adicionar cidade…")]
        case .alerts: [L("Alertas"), L("Disco quase cheio"), L("Bateria baixa"), L("Memória no limite"), L("CPU alta por muito tempo"),
                       L("Mac esquentando"), L("Bateria dos acessórios"), L("App descontrolado")]
        case .links: [L("Links rápidos"), "Google", "GitHub"]
        case .privacy: [L("Permissões"), L("Acessibilidade")]
        case .backup: [L("Backup"), L("Incluir notas"), L("Incluir histórico do clipboard"), L("Exportar…"), L("Restaurar…")]
        case .about: [L("Atualizações"), L("Procurar atualizações automaticamente"), L("Reportar um problema…"), L("Sugerir uma ideia…"),
                      L("Pagar um café ao autor ☕"), L("Ver a apresentação de novo"), L("Sair do Menew")]
        }
        return ([title] + words).joined(separator: " ")
    }
}

/// Janela própria de Ajustes, como os Ajustes do Sistema: categorias na lateral e busca
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(_ category: SettingsCategory? = nil) {
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        guard let app = NSApp.delegate as? AppDelegate else { return }
        let w = window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = L("Ajustes do Menew")
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 640, height: 420)
            w.delegate = self
            w.contentView = NSHostingView(rootView: SettingsWindowView(clipboard: app.clipboard, monitor: app.monitor, updater: app.updater,
                                                                       initial: category ?? .general))
            // Na primeira vez abre no centro da tela; depois, onde você deixou
            w.setContentSize(NSSize(width: 760, height: 560))
            if !w.setFrameUsingName("MenewSettings") { w.center() }
            w.setFrameAutosaveName("MenewSettings")
            return w
        }()
        window = w
        if let category { NotificationCenter.default.post(name: .settingsCategory, object: category.rawValue) }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let settingsCategory = Notification.Name("MenewSettingsCategory")
}

struct SettingsWindowView: View {
    @ObservedObject var clipboard: ClipboardManager
    let monitor: SystemMonitor
    @ObservedObject var updater: UpdaterModel
    @State private var selection: SettingsCategory
    @State private var query = ""
    @AppStorage("language") private var language = "auto"

    init(clipboard: ClipboardManager, monitor: SystemMonitor, updater: UpdaterModel, initial: SettingsCategory) {
        self.clipboard = clipboard
        self.monitor = monitor
        self.updater = updater
        _selection = State(initialValue: initial)
    }

    private var visible: [SettingsCategory] {
        let q = PaletteSearch.fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return SettingsCategory.allCases }
        return SettingsCategory.allCases.filter { PaletteSearch.fold($0.keywords).contains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField(L("Buscar"), text: $query).textFieldStyle(.plain).font(.system(size: 13))
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.tertiary)
                            .accessibilityLabel(L("Limpar busca"))
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(visible) { c in
                            Button { selection = c } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: c.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(c.color.gradient))
                                    Text(c.title).font(.system(size: 13)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(selection == c ? Color.accentColor.opacity(0.18) : .clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if visible.isEmpty {
                            Text(L("Nada encontrado")).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 10).padding(.top, 38).padding(.bottom, 10)
            .frame(width: 220)
            .background(VisualEffect(material: .sidebar).ignoresSafeArea())

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(selection.title).font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 12)
                SettingsView(clipboard: clipboard, monitor: monitor, updater: updater, category: selection)
                    .padding(.horizontal, 10)
                    .id(selection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.windowFill)
        }
        .ignoresSafeArea()
        .onChange(of: query) { _, _ in
            // A busca leva à primeira categoria que tem o ajuste
            if let first = visible.first, !visible.contains(selection) { selection = first }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsCategory)) { n in
            if let raw = n.object as? String, let c = SettingsCategory(rawValue: raw) { selection = c; query = "" }
        }
        .id(language)
    }
}
