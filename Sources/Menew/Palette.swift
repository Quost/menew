import AppKit
import Carbon
import SwiftUI

// MARK: Itens

/// Uma coisa que a paleta encontra e executa: ação do Menew, app, layout de janela, snippet, nota ou item copiado
struct PaletteItem: Identifiable {
    enum Kind: Int {
        case calc, action, profile, window, app, snippet, note, clip

        var label: String {
            switch self {
            case .calc: L("Calculadora")
            case .action: L("Ação")
            case .profile: L("Perfil")
            case .window: L("Janela")
            case .app: L("App")
            case .snippet: L("Snippet")
            case .note: L("Nota")
            case .clip: L("Clipboard")
            }
        }
    }

    enum Icon {
        case symbol(String, Color)
        case app(String)            // caminho do .app
        case layout(WindowLayout)
    }

    let id: String
    let kind: Kind
    let title: String
    var subtitle: String?
    /// Palavras extras para a busca (sinônimos, outros idiomas)
    var keywords = ""
    let icon: Icon
    var shortcut: String?
    /// Fica entre os recentes (itens do clipboard não ficam, por privacidade)
    var remember = true
    /// Não fecha a paleta (buscar a cotação e mostrar o resultado ali mesmo)
    var keepOpen = false
    let run: () -> Void
}

// MARK: Apps instalados

@MainActor
enum AppIndex {
    struct App { let name: String; let path: String }
    private static var cache: [App] = []
    private static var loadedAt: Date?
    private static var icons: [String: NSImage] = [:]

    /// Lê as pastas de apps de novo a cada minuto, no máximo
    static func all() -> [App] {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return cache }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var seen = Set<String>()
        var out: [App] = []
        func add(_ path: String) {
            let name = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            guard !seen.contains(name), path != Bundle.main.bundlePath else { return }
            seen.insert(name)
            out.append(App(name: name, path: path))
        }
        for dir in ["/Applications", "/Applications/Utilities", "/System/Applications",
                    "/System/Applications/Utilities", home + "/Applications"] {
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where !name.hasPrefix(".") {
                let path = dir + "/" + name
                if name.hasSuffix(".app") {
                    add(path)
                } else if dir == "/Applications" || dir == home + "/Applications" { // pastas como "Microsoft Office"
                    for sub in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where sub.hasSuffix(".app") {
                        add(path + "/" + sub)
                    }
                }
            }
        }
        add("/System/Library/CoreServices/Finder.app")
        cache = out
        loadedAt = Date()
        return out
    }

    static func icon(_ path: String) -> NSImage {
        if let i = icons[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        icons[path] = i
        return i
    }
}

// MARK: Busca

enum PaletteSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(_ s: String) -> [Substring] {
        s.split { !$0.isLetter && !$0.isNumber }
    }

    /// nil = não combina. Quanto maior, mais para cima.
    static func score(_ query: String, title: String, keywords: String) -> Int? {
        let t = fold(title)
        let tokens = query.split(separator: " ")
        if tokens.count > 1 { // "janela esquerda": todas as palavras precisam aparecer
            let hay = words(t + " " + fold(keywords))
            return tokens.allSatisfy { tk in hay.contains { $0.hasPrefix(tk) } } ? 500 : nil
        }
        let q = query
        if t == q { return 1000 }
        if t.hasPrefix(q) { return 800 - t.count }
        let ws = words(t)
        if ws.contains(where: { $0.hasPrefix(q) }) { return 650 - t.count }
        if q.count >= 2, String(ws.compactMap(\.first)).hasPrefix(q) { return 600 } // "mt" → Microsoft Teams
        if t.contains(q) { return 450 - t.count }
        if words(fold(keywords)).contains(where: { $0.hasPrefix(q) }) { return 350 }
        if q.count >= 3, isSubsequence(q, of: t) { return 150 - t.count }
        return nil
    }

    private static func isSubsequence(_ q: String, of t: String) -> Bool {
        var it = t.makeIterator()
        return q.allSatisfy { c in while let x = it.next() { if x == c { return true } }; return false }
    }
}

// MARK: Modelo

@MainActor
final class PaletteModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { selection = 0; update() } } }
    @Published var selection = 0
    @Published private(set) var results: [PaletteItem] = []
    @Published var focusToken = 0

    let toolbox: Toolbox
    let clipboard: ClipboardManager
    let notes: NotesStore
    var openTab: (Tab) -> Void = { _ in }
    var openNote: (UUID) -> Void = { _ in }
    var openClipboard: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var openShelf: () -> Void = {}
    /// Fecha a paleta antes de executar
    var dismiss: () -> Void = {}
    /// Modo captura: apps fixos e nada de recentes reais
    var isDemo = false

    private static let recentsKey = "paletteRecents"

    init(toolbox: Toolbox, clipboard: ClipboardManager, notes: NotesStore) {
        self.toolbox = toolbox
        self.clipboard = clipboard
        self.notes = notes
        // As portas chegam depois do lsof; a lista se atualiza se a busca estiver mostrando alguma
        Ports.shared.onChange = { [weak self] in if self?.query.isEmpty == false { self?.update() } }
    }

    func reset() {
        toolbox.refresh()
        if Module.actions.isOn { Ports.shared.refresh() }
        query = ""
        selection = 0
        update()
        focusToken += 1
    }

    func run(_ index: Int) {
        guard results.indices.contains(index) else { return }
        let item = results[index]
        if item.keepOpen { item.run(); return }
        if item.remember && !isDemo { remember(item.id) }
        dismiss()
        // Deixa o painel sumir e o app da frente voltar a receber o teclado
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { item.run() }
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    // MARK: Resultados

    func update() {
        let q = PaletteSearch.fold(query.trimmingCharacters(in: .whitespaces))
        let recents = isDemo ? Self.demoRecents : (UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [])
        var pool = commands()
        if q.isEmpty {
            // Sem busca: recentes primeiro, depois sugestões
            let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let recent = recents.compactMap { byID[$0] }
            let suggested = Self.suggestions.compactMap { byID[$0] }.filter { s in !recent.contains { $0.id == s.id } }
            results = Array((recent + suggested).prefix(12))
            return
        }
        pool += parametric(q)
        pool += devItems(q)
        pool += QuickLinkStore.shared.paletteItems(raw: query)
        if let ask = AIText.askItem(raw: query) { pool.append(ask) }
        if Module.clipboard.isOn, let text = TextTransform.clipboardText() {
            pool += TextTransform.paletteItems(text: text, query: q)
            pool += AIText.paletteItems(text: text, query: q)
        }
        if Module.clipboard.isOn {
            pool += clipboard.filtered(query).prefix(6).map { item in
                PaletteItem(id: "clip.\(item.id)", kind: .clip, title: item.title.isEmpty ? item.preview : item.title,
                            subtitle: item.sourceApp, icon: .symbol(Self.clipIcon(item), .gray), remember: false) { [clipboard] in
                    clipboard.paste(item)
                }
            }
        }
        // Contas e conversões ficam sempre no topo
        let calc = calculatorItems(q)
        let scored: [(PaletteItem, Int)] = pool.compactMap { item in
            // Clipboard já veio filtrado; contas, horários e timestamps vêm da própria busca e ficam no topo
            let base = item.kind == .clip ? 200 : item.kind == .calc ? 900 : PaletteSearch.score(q, title: item.title, keywords: item.keywords)
            guard let base else { return nil }
            let bonus = recents.firstIndex(of: item.id).map { max(0, 60 - $0 * 3) } ?? 0
            return (item, base + bonus)
        }
        results = calc + scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.kind.rawValue < $1.0.kind.rawValue }
            .prefix(40).map(\.0)
        // Sempre por último: buscar o texto na web
        if let search = QuickLinkStore.shared.webSearchItem(raw: query) { results.append(search) }
    }

    /// Para quem programa: portas em uso ("porta", "3000") e timestamps Unix ("1793400000" vira data)
    private func devItems(_ q: String) -> [PaletteItem] {
        guard Module.actions.isOn else { return [] }
        var out: [PaletteItem] = []
        let ports = Ports.shared.list
        let wantsAll = ["porta", "portas", "port", "ports", "lsof", "localhost", "servidor", "server", "puerto", "puertos", "端口"]
            .contains { $0.hasPrefix(q) && q.count >= 3 }
        for p in ports where wantsAll || String(p.port).hasPrefix(q) {
            let name = p.name
            out.append(PaletteItem(id: "port.\(p.port)", kind: .action, title: L("Parar %@ na porta %d", name, p.port),
                                   subtitle: L("Processo %d", Int(p.pid)), keywords: q,
                                   icon: .symbol("network", .indigo), remember: false) { Ports.shared.stop(p) })
        }
        if let (date, from, to) = WorldClock.paletteQuery(q) {
            let there = WorldClock.time(date, in: to)
            let here = from == .current && to != .current
                ? L("%@ aqui", WorldClock.time(date, in: .current))
                : L("%@ em %@", WorldClock.time(date, in: from), WorldClock.city(from))
            let day = WorldClock.dayNote(date, in: to, from: from).map { " · " + $0 } ?? ""
            out.append(PaletteItem(id: "clock.\(to.identifier)", kind: .calc, title: L("%@ em %@", there, WorldClock.city(to)),
                                   subtitle: here + " · " + WorldClock.offset(to, at: date, from: from) + day, keywords: q,
                                   icon: .symbol("globe", .teal), remember: false) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(there, forType: .string)
                HUD.show(icon: "doc.on.doc.fill", color: .gray, text: L("Copiado: %@", there))
            })
        }
        if q.allSatisfy(\.isNumber), q.count == 10 || q.count == 13, let n = Double(q) {
            let date = Date(timeIntervalSince1970: q.count == 13 ? n / 1000 : n)
            let text = date.formatted(.dateTime.day().month().year().hour().minute().second().locale(L10n.locale))
            let iso = date.ISO8601Format()
            out.append(PaletteItem(id: "timestamp.date", kind: .calc, title: text, subtitle: L("Timestamp Unix · ↩ copia %@", iso),
                                   keywords: q, icon: .symbol("calendar.badge.clock", .gray), remember: false) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(iso, forType: .string)
                HUD.show(icon: "doc.on.doc.fill", color: .gray, text: L("Copiado: %@", iso))
            })
        }
        return out
    }

    /// "12*7,5", "20% de 340", "5 km em mi" e "100 usd em brl"
    private func calculatorItems(_ q: String) -> [PaletteItem] {
        func copyItem(_ value: String, _ detail: String, id: String) -> PaletteItem {
            PaletteItem(id: id, kind: .calc, title: value, subtitle: detail, icon: .symbol("equal", .gray), remember: false) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(value, forType: .string)
                HUD.show(icon: "doc.on.doc.fill", color: .gray, text: L("Copiado: %@", value))
            }
        }
        if let (v, from, to) = Calculator.currencyQuery(q) {
            let detail = Calculator.currencyText(v, from)
            if let rate = Calculator.cachedRate(from, to) {
                return [copyItem(Calculator.currencyText(v * rate, to), detail + " · " + L("cotação do BCE"), id: "calc.fx")]
            }
            // A internet só é usada quando você pede
            return [PaletteItem(id: "calc.fx.fetch", kind: .calc, title: L("Converter %@ em %@", detail, to),
                                subtitle: L("↩ busca a cotação do dia (frankfurter.app)"), icon: .symbol("dollarsign.arrow.circlepath", .green),
                                remember: false, keepOpen: true) { [weak self] in
                Task {
                    if await Calculator.fetchRate(from, to) == nil {
                        HUD.show(icon: "wifi.exclamationmark", color: .orange, text: L("Não deu para buscar a cotação"))
                    }
                    self?.update()
                }
            }]
        }
        guard let r = Calculator.evaluate(q) else { return [] }
        return [copyItem(r.value, r.detail, id: "calc")]
    }

    private func remember(_ id: String) {
        var list = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        list.removeAll { $0 == id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(20)), forKey: Self.recentsKey)
    }

    private static let suggestions = ["action.awake", "action.mic", "action.dark", "action.clipboard",
                                      "win.maximize", "win.leftHalf", "win.rightHalf", "action.cleaner"]
    private static let demoRecents = ["app:/System/Applications/Notes.app", "win.leftHalf", "snippet.demo",
                                      "action.mic", "app:/System/Applications/Calendar.app"]

    private static func clipIcon(_ item: ClipItem) -> String {
        switch item.kind {
        case .image: "photo"
        case .file: "doc"
        case .text: item.url != nil ? "link" : "doc.text"
        }
    }

    // MARK: Catálogo

    /// Tudo o que dá para executar agora (as ações respeitam os módulos ligados)
    private func commands() -> [PaletteItem] {
        let tb = toolbox
        var out: [PaletteItem] = []
        func action(_ id: String, _ title: String, _ icon: String, _ color: Color, _ keywords: String,
                    subtitle: String? = nil, shortcut: String? = nil, run: @escaping () -> Void) {
            out.append(PaletteItem(id: "action.\(id)", kind: .action, title: title, subtitle: subtitle, keywords: keywords,
                                   icon: .symbol(icon, color), shortcut: shortcut, run: run))
        }

        if Module.actions.isOn {
            let micKey = Shortcut.load(HotKeyCenter.micKey, default: .micDefault).display
            action("mic", tb.micMuted ? L("Ligar microfone") : L("Mutar microfone"), tb.micMuted ? "mic.slash.fill" : "mic.fill", .red,
                   "mic microphone microfone mute mudo silenciar reunião meeting", shortcut: micKey) {
                MuteHUD.show(muted: tb.toggleMic())
            }
            action("sound", tb.soundMuted ? L("Ligar som") : L("Mutar som"), tb.soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", .pink,
                   "sound som volume audio áudio mute mudo") {
                tb.toggleSound()
                HUD.show(icon: tb.soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", color: .pink,
                         text: tb.soundMuted ? L("Som mudo") : L("Som ligado"))
            }
            action("dark", tb.darkMode ? L("Modo claro") : L("Modo escuro"), tb.darkMode ? "sun.max.fill" : "moon.fill", .indigo,
                   "dark mode escuro claro light tema theme aparência appearance") { tb.toggleDarkMode() }
            let presenting = PresentationMode.shared.isOn
            action("presentation", presenting ? L("Desligar modo apresentação") : L("Modo apresentação"), "play.rectangle.fill", .green,
                   "apresentação apresentar presentation present compartilhar share tela screen reunião meeting präsentation presentación 演示",
                   subtitle: presenting ? nil : L("Esconde a mesa, mantém acordado e pausa o clipboard")) { PresentationMode.shared.toggle() }
            let audio = AudioRouter.shared
            audio.refresh()
            for d in audio.outputs where d.id != audio.output {
                action("out.\(d.name)", L("Saída de som: %@", d.name), d.icon(input: false), .blue,
                       "som saída output audio áudio speaker fone headphone airpods caixa ausgabe salida 输出 \(d.name)") { audio.select(d, input: false) }
            }
            for d in audio.inputs where d.id != audio.input {
                action("in.\(d.name)", L("Microfone: %@", d.name), d.icon(input: true), .red,
                       "microfone mic input entrada audio áudio mikrofon micrófono 麦克风 \(d.name)") { audio.select(d, input: true) }
            }
            action("awake", tb.keepAwake ? L("Desligar manter acordado") : L("Manter acordado"), "cup.and.saucer.fill", .orange,
                   "awake acordado caffeine cafe café sleep dormir tela amphetamine",
                   subtitle: tb.keepAwake ? nil : L("Digite um tempo, como “acordado 2h”")) {
                tb.setKeepAwake(!tb.keepAwake)
                HUD.show(icon: "cup.and.saucer.fill", color: .orange,
                         text: tb.keepAwake ? L("Mantendo o Mac acordado") : L("Manter acordado desligado"))
            }
            action("hidden", tb.hiddenFiles ? L("Esconder arquivos ocultos") : L("Mostrar arquivos ocultos"), "eye.fill", .blue,
                   "hidden ocultos arquivos files finder dotfiles") { tb.toggleHiddenFiles() }
            action("desktop", tb.desktopIconsHidden ? L("Mostrar ícones da mesa") : L("Esconder ícones da mesa"), "menubar.dock.rectangle", .teal,
                   "desktop mesa ícones icons apresentar gravar") { tb.toggleDesktopIcons() }
            action("dock", tb.dockAutohide ? L("Mostrar o Dock sempre") : L("Esconder o Dock"), "dock.rectangle", .gray,
                   "dock esconder hide autohide") { tb.toggleDockAutohide() }
            action("cleaner", L("Liberar espaço"), "sparkles", .blue, "cleaner limpar espaço disco disk cache lixo") { [weak self] in
                self?.openTab(.cleaner)
            }
            action("keyboard", L("Limpar teclado"), "keyboard", .teal, "teclado keyboard limpar travar lock clean") {
                if !tb.cleaning.lockKeyboard() { ClipboardManager.requestAccessibility() }
            }
            action("screen", L("Limpar tela"), "sparkles.tv", .cyan, "tela screen limpar preta black clean") { tb.cleaning.blackScreen() }
            if let m = MeetingStore.shared.next, m.link != nil {
                action("meeting", L("Entrar na reunião"), "video.fill", .orange, "reunião meeting entrar join zoom meet teams call chamada",
                       subtitle: m.title) { MeetingStore.shared.join() }
            }
            action("quitall", L("Fechar todos os apps"), "xmark.circle.fill", .red,
                   "fechar todos quit all close apps encerrar sair alle beenden cerrar todas 退出 全部") {
                AppControl.quitAllWithNotice(others: false)
            }
            if let front = AppControl.front?.localizedName {
                action("quitothers", L("Fechar os outros apps"), "rectangle.portrait.and.arrow.right.fill", .orange,
                       "fechar outros quit others close other apps andere beenden cerrar otras 退出 其他",
                       subtitle: L("menos %@", front)) { AppControl.quitAllWithNotice(others: true) }
            }
            action("hideothers", L("Esconder os outros apps"), "eye.slash.fill", .gray,
                   "esconder outros hide others andere ausblenden ocultar otras 隐藏 其他") { AppControl.hideOthers() }
            let focus = FocusTimer.shared
            if focus.isRunning {
                action("focus", L("Parar foco"), "stop.fill", .red, "foco focus pomodoro parar stop timer") { focus.stop() }
            } else {
                action("focus", L("Iniciar foco"), "timer", .red, "foco focus pomodoro concentrar timer",
                       subtitle: L("Digite um tempo, como “foco 50”")) { focus.start(minutes: 25) }
            }
            if Module.clipboard.isOn {
                let queue = PasteQueue.shared
                action("pastequeue", queue.isOn ? L("Parar a fila de colagem") : L("Fila de colagem"), "list.number", .purple,
                       "fila queue colar paste sequência sequence stack pilha vários multiple warteschlange cola 队列 粘贴",
                       subtitle: queue.isOn ? nil : L("Copie vários itens e cole um por um com ⌘V")) { queue.toggle() }
            }
            action("ocr", L("Copiar texto da tela"), "text.viewfinder", .green, "ocr texto text capturar capture scan ler read textsniper",
                   shortcut: Shortcut.load(HotKeyCenter.ocrKey, default: .ocrDefault).display) { TextRecognizer.captureScreenText() }
            action("screenshot", L("Capturar tela"), "camera.viewfinder", .pink, "print screenshot captura capturar tela imagem anotar annotate cleanshot bildschirmfoto captura 截图",
                   subtitle: L("Área ou janela, com anotações"),
                   shortcut: Shortcut.load(ScreenCapture.key, default: .captureDefault).display) { ScreenCapture.area() }
            action("screenshotfull", L("Capturar a tela inteira"), "display", .pink, "print screenshot tela inteira full screen captura") { ScreenCapture.fullScreen() }
            let meetings = MeetingStore.shared
            if meetings.isOn {
                action("freeslots", L("Copiar meus horários livres"), "calendar.badge.checkmark", .green,
                       "horários livres agenda disponibilidade free slots availability calendar calendário reunião meeting freie zeiten disponibilidad 空闲时间",
                       subtitle: L("Próximos 5 dias úteis, prontos para mandar")) { meetings.copyFreeSlots() }
                for m in meetings.today where m.end > Date() {
                    let time = m.start.formatted(.dateTime.hour().minute().locale(L10n.locale))
                    action("meeting.\(m.id)", "\(time) · \(m.title)", m.link != nil ? "video.fill" : "calendar", .orange,
                           "agenda hoje today reunião reuniao meeting calendário calendar heute hoy 今天 \(m.title)",
                           subtitle: m.link != nil ? L("Entrar na reunião") : L("Abrir no Calendário")) { meetings.open(m) }
                }
            }
            action("uuid", L("Gerar UUID"), "number.square.fill", .gray, "uuid guid id gerar generate novo new erzeugen generar 生成") {
                let id = UUID().uuidString.lowercased()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(id, forType: .string)
                HUD.show(icon: "doc.on.doc.fill", color: .gray, text: L("Copiado: %@", id))
            }
            action("timestamp", L("Copiar timestamp Unix"), "clock.badge.checkmark.fill", .gray,
                   "timestamp unix epoch agora now segundos seconds zeitstempel marca tiempo 时间戳",
                   subtitle: String(Int(Date().timeIntervalSince1970))) {
                let ts = String(Int(Date().timeIntervalSince1970))
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ts, forType: .string)
                HUD.show(icon: "doc.on.doc.fill", color: .gray, text: L("Copiado: %@", ts))
            }
            action("color", L("Conta-gotas"), "eyedropper.halffull", Theme.violet, "cor color picker hex conta-gotas eyedropper") { [clipboard] in
                tb.pickColor(clipboard: clipboard)
            }
            action("plain", L("Limpar formatação"), "textformat", .brown, "formatação texto puro plain text format") {
                tb.plainTextClipboard()
                HUD.show(icon: "textformat", color: .brown, text: L("Formatação removida"))
            }
            action("shelf", L("Abrir a estante"), "tray.full.fill", Theme.indigo,
                   "estante shelf dropover arquivos files arrastar drag ablage estantería") { [weak self] in self?.openShelf() }
            action("lock", L("Bloquear tela"), "lock.fill", .gray, "bloquear lock tela screen senha") { tb.lockScreen() }
            if tb.ejectableCount > 0 {
                action("eject", L("Ejetar discos"), "eject.fill", .mint, "ejetar eject disco pendrive usb") { tb.ejectAll() }
            }
            action("trash", L("Esvaziar lixeira"), "trash", .red, "lixeira trash esvaziar empty") { tb.emptyTrash() }

            for p in ProfileStore.shared.profiles {
                out.append(PaletteItem(id: "profile.\(p.id)", kind: .profile, title: p.name, subtitle: p.apps.map(\.name).joined(separator: ", "),
                                       keywords: "perfil profile workspace \(p.apps.map(\.name).joined(separator: " "))",
                                       icon: .symbol(p.icon, .indigo)) {
                    ProfileStore.shared.activate(p, toolbox: tb)
                })
            }

            for l in WindowLayout.allCases where l != .nextDisplay || NSScreen.screens.count > 1 {
                out.append(PaletteItem(id: "win.\(l.rawValue)", kind: .window, title: l.title,
                                       keywords: "janela window layout \(l.rawValue)", icon: .layout(l),
                                       shortcut: WindowManager.shortcutsOn ? l.shortcutDisplay : nil) {
                    WindowManager.shared.apply(l)
                })
            }
        }

        if Module.clipboard.isOn {
            action("clipboard", L("Histórico do clipboard"), "doc.on.clipboard", Theme.violet, "clipboard histórico history copiar colar paste",
                   shortcut: Shortcut.load(HotKeyCenter.clipboardKey, default: .clipboardDefault).display) { [weak self] in
                self?.openClipboard()
            }
            if ClipboardManager.isPaused {
                action("clipresume", L("Retomar captura do clipboard"), "play.circle.fill", .orange, "clipboard retomar resume pausa pause") {
                    ClipboardManager.resume()
                    HUD.show(icon: "play.circle.fill", color: .green, text: L("Captura retomada"))
                }
            } else {
                action("clippause", L("Pausar o clipboard por 1 hora"), "pause.circle.fill", .orange,
                       "clipboard pausar pause privacidade privacy") {
                    ClipboardManager.pause(minutes: 60)
                    HUD.show(icon: "pause.circle.fill", color: .orange, text: L("Clipboard pausado por 1 hora"))
                }
            }
            for s in clipboard.snippets.snippets {
                let item = ClipItem(id: s.id, kind: .text, text: s.text, snippetTitle: s.title)
                out.append(PaletteItem(id: isDemo && s.id == clipboard.snippets.snippets.first?.id ? "snippet.demo" : "snippet.\(s.id)",
                                       kind: .snippet, title: s.title, subtitle: item.preview, keywords: "snippet \(s.text)",
                                       icon: .symbol("text.badge.star", .orange)) { [clipboard] in
                    clipboard.paste(item)
                })
            }
        }

        if Module.notes.isOn {
            for n in notes.notes {
                out.append(PaletteItem(id: "note.\(n.id)", kind: .note, title: n.title, subtitle: n.preview,
                                       keywords: n.secure ? "" : n.text, icon: .symbol(n.isPasswords ? "key.fill" : n.secure ? "lock.fill" : "note.text", n.isPasswords ? .blue : .yellow)) { [weak self] in
                    self?.openNote(n.id)
                })
            }
        }

        action("system", L("Monitor do sistema"), "gauge.with.dots.needle.67percent", .green,
               "sistema system cpu memória memory ram bateria battery rede network monitor") { [weak self] in self?.openTab(.system) }
        action("settings", L("Ajustes do Menew"), "gearshape.fill", .gray, "ajustes settings preferências preferences config") { [weak self] in
            self?.openTab(.settings)
        }
        action("update", L("Procurar atualizações…"), "arrow.down.circle", .blue, "update atualizar atualização versão version") { [weak self] in
            self?.checkForUpdates()
        }

        for app in isDemo ? Self.demoApps : AppIndex.all() {
            out.append(PaletteItem(id: "app:\(app.path)", kind: .app, title: app.name, icon: .app(app.path)) {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: .init())
            })
        }
        return out
    }

    private static let demoApps = [("Notes", "Notes"), ("Calendar", "Calendar"), ("Music", "Music"), ("Safari", "Safari")]
        .map { AppIndex.App(name: FileManager.default.displayName(atPath: "/System/Applications/\($0.1).app")
                                .replacingOccurrences(of: ".app", with: ""), path: "/System/Applications/\($0.1).app") }

    /// "brilho 60", "acordado 2h": ações com um número digitado
    private func parametric(_ q: String) -> [PaletteItem] {
        guard Module.actions.isOn else { return [] }
        let tb = toolbox
        var out: [PaletteItem] = []
        let parts = q.split(separator: " ")
        // "acordado até 18", "awake until 18:30"
        if parts.count == 3, ["acordado", "awake", "wach", "despierto"].contains(where: { $0.hasPrefix(String(parts[0])) }),
           ["ate", "until", "bis", "hasta"].contains(String(parts[1])) {
            let hm = parts[2].replacingOccurrences(of: "h", with: ":").split(separator: ":").compactMap { Int($0) }
            if let h = hm.first, (0..<24).contains(h) {
                let m = hm.count > 1 ? hm[1] : 0
                if (0..<60).contains(m),
                   let date = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: h, minute: m), matchingPolicy: .nextTime) {
                    let time = date.formatted(.dateTime.hour().minute().locale(L10n.locale))
                    out.append(PaletteItem(id: "awake.until", kind: .action, title: L("Manter acordado até %@", time), keywords: q,
                                           icon: .symbol("cup.and.saucer.fill", .orange), remember: false) {
                        tb.keepAwake(until: date)
                        HUD.show(icon: "cup.and.saucer.fill", color: .orange, text: L("Acordado até %@", time))
                    })
                }
            }
            return out
        }
        guard parts.count == 2 else { return [] }
        let word = String(parts[0]), arg = String(parts[1])

        if ["brilho", "brightness", "helligkeit", "brillo", "亮度"].contains(where: { $0.hasPrefix(word) }),
           let n = Int(arg.trimmingCharacters(in: CharacterSet(charactersIn: "%"))), (0...100).contains(n) {
            let screens = tb.displays.screens.filter { $0.kind != .unsupported }
            if !screens.isEmpty {
                out.append(PaletteItem(id: "brightness", kind: .action, title: L("Brilho em %d%%", n), keywords: word,
                                       icon: .symbol("sun.max.fill", .yellow), remember: false) {
                    for s in screens { tb.displays.set(Double(n) / 100, for: s.id) }
                    HUD.show(icon: "sun.max.fill", color: .yellow, text: L("Brilho em %d%%", n))
                })
            }
        }

        if ["acordado", "awake", "wach", "despierto", "caffeine", "cafe"].contains(where: { $0.hasPrefix(word) }) {
            // "90", "90m", "90min", "2h"
            let digits = Int(arg.prefix { $0.isNumber })
            let unit = arg.drop { $0.isNumber }
            if let digits, digits > 0, ["", "m", "min", "h"].contains(unit) {
                let minutes = unit == "h" ? digits * 60 : digits
                let label = minutes % 60 == 0 ? (minutes == 60 ? L("1 hora") : L("%d horas", minutes / 60)) : L("%d minutos", minutes)
                out.append(PaletteItem(id: "awake.timed", kind: .action, title: L("Manter acordado por %@", label), keywords: word,
                                       icon: .symbol("cup.and.saucer.fill", .orange), remember: false) {
                    tb.setKeepAwake(true, minutes: minutes)
                    HUD.show(icon: "cup.and.saucer.fill", color: .orange, text: L("Acordado por %@", label))
                })
            }
        }
        if ["foco", "focus", "fokus", "pomodoro", "专注"].contains(where: { $0.hasPrefix(word) }),
           let minutes = Int(arg.prefix { $0.isNumber }), (1...600).contains(minutes) {
            out.append(PaletteItem(id: "focus.timed", kind: .action, title: L("Foco por %d min", minutes), keywords: word,
                                   icon: .symbol("timer", .red), remember: false) {
                FocusTimer.shared.start(minutes: minutes)
            })
        }
        return out.map { item in var i = item; i.keywords = q; return i }
    }
}

// MARK: Tela

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @FocusState private var focused: Bool
    @AppStorage("language") private var language = "auto"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(L("Buscar apps, ações, snippets e notas"), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)

            Divider().opacity(0.6)

            if model.results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text(L("Nada encontrado para “%@”", model.query)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if model.query.isEmpty {
                        Text(L("Recentes e sugestões"))
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 2)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(model.results.enumerated()), id: \.element.id) { i, item in
                                    PaletteRow(item: item, index: i, selected: i == model.selection)
                                        .contentShape(Rectangle())
                                        .onTapGesture { model.run(i) }
                                }
                            }
                            .padding(8)
                        }
                        .scrollIndicators(.never)
                        .onChange(of: model.selection) { _, s in
                            if model.results.indices.contains(s) { proxy.scrollTo(model.results[s].id) }
                        }
                    }
                }
            }

            Divider().opacity(0.6)
            HStack(spacing: 14) {
                hint("↑↓", L("navegar"))
                hint("↩", L("abrir"))
                hint("⌘1–9", L("rápido"))
                hint("esc", L("fechar"))
                Spacer()
                Text("Menew").foregroundStyle(.tertiary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 16).padding(.vertical, 9)
        }
        .id(language)
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { _, _ in focused = true }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Keycap(text: key)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

struct PaletteRow: View {
    let item: PaletteItem
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                if let s = item.subtitle, !s.isEmpty {
                    Text(s).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let k = item.shortcut { Keycap(text: k) }
            Text(item.kind.label).font(.system(size: 11)).foregroundStyle(.tertiary)
            if index < 9 {
                Text("⌘\(index + 1)").font(.system(size: 10.5, design: .rounded)).foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: item.subtitle?.isEmpty == false ? 44 : 38)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.22) : .clear))
    }

    @ViewBuilder private var icon: some View {
        switch item.icon {
        case .symbol(let name, let color):
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
        case .app(let path):
            Image(nsImage: AppIndex.icon(path)).resizable().interpolation(.high)
        case .layout(let l):
            LayoutIcon(layout: l).padding(.vertical, 3)
        }
    }
}

// MARK: Janela

@MainActor
final class PaletteController: NSObject, NSWindowDelegate {
    let model: PaletteModel
    private var panel: KeyPanel?
    private var monitor: Any?
    static let size = NSSize(width: 640, height: 430)

    init(model: PaletteModel) {
        self.model = model
        super.init()
        model.dismiss = { [weak self] in self?.close() }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? close() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reset()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.midX - Self.size.width / 2, y: vf.minY + vf.height * 0.62 - Self.size.height / 2))
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.1; panel.animator().alphaValue = 1 }
        installMonitor()
    }

    func close() {
        panel?.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func makePanel() -> KeyPanel {
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                         styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: Self.chrome(PaletteView(model: model)))
        return p
    }

    /// Fundo, cantos e borda (também usados no modo captura)
    static func chrome<V: View>(_ v: V) -> some View {
        v.frame(width: size.width, height: size.height)
            .background(VisualEffect(material: .popover))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    private func installMonitor() {
        if monitor != nil { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            nonisolated(unsafe) let e = event
            return MainActor.assumeIsolated {
                guard let self, e.window === self.panel else { return e }
                return self.handle(e) ? nil : e
            }
        }
    }

    /// true = evento consumido
    private func handle(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch Int(e.keyCode) {
        case kVK_Escape: close(); return true
        case kVK_DownArrow: model.move(1); return true
        case kVK_UpArrow: model.move(-1); return true
        case kVK_Return, kVK_ANSI_KeypadEnter: model.run(model.selection); return true
        default: break
        }
        if e.modifierFlags.contains(.control), let ch = e.charactersIgnoringModifiers {
            if ch == "n" { model.move(1); return true }
            if ch == "p" { model.move(-1); return true }
        }
        if cmd, let ch = e.charactersIgnoringModifiers?.lowercased() {
            if let n = Int(ch), (1...9).contains(n) { model.run(n - 1); return true }
            if ch == "w" { close(); return true }
        }
        return false
    }
}
