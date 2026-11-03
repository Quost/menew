import AppKit
import SwiftUI

/// Reescrever em qualquer app: selecione um texto (Mail, Slack, Notion…), aperte ⌃⌥⌘R, escolha "corrigir",
/// "mais formal", "mais curto"… e o texto novo entra no lugar do selecionado. O clipboard volta a ser o que era.
/// Usa a IA do Mac e a permissão de Acessibilidade; nada sai do Mac.
@MainActor
final class Rewriter: ObservableObject {
    static let shared = Rewriter()
    static let options: [AIAction] = [.fix, .clearer, .formal, .friendly, .shorter, .toEnglish]

    @Published var original = ""
    @Published var result = ""
    @Published var chosen: AIAction?
    @Published var chosenAction: SelectionAction?
    /// O app de onde veio o texto (para a memória)
    private var origin = MemoryOrigin()
    @Published var working = false
    @Published var failed = false
    private var panel: NSPanel?
    private var savedClipboard: [[NSPasteboard.PasteboardType: Data]] = []

    /// Copia a seleção do app da frente (⌘C) e abre as opções perto do mouse
    func start() {
        guard AIFeature.rewrite.isOn else { return }
        // Sem Apple Intelligence ainda dá para virar nota ou ir para a memória
        guard AXIsProcessTrusted() else {
            HUD.show(icon: "hand.raised.fill", color: .orange, text: L("Libere o Menew em Acessibilidade"), duration: 2.5)
            return
        }
        origin = MemoryOrigin.current()
        let pb = NSPasteboard.general
        savedClipboard = Self.snapshot(pb)
        let before = pb.changeCount
        Self.postCommand(8) // C
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard pb.changeCount != before, let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                HUD.show(icon: "character.cursor.ibeam", color: .orange, text: L("Selecione um texto primeiro"), duration: 2)
                return
            }
            original = text
            result = ""
            chosen = nil
            chosenAction = nil
            failed = false
            show()
        }
    }

    var aiAvailable: Bool { AIText.unavailableReason == nil }

    func choose(_ action: AIAction) {
        guard !working else { return }
        chosen = action
        chosenAction = nil
        result = ""
        failed = false
        working = true
        Task {
            do { result = try await AIText.generate(action, original) } catch { failed = true }
            working = false
        }
    }

    /// Ações que não reescrevem: explicam, documentam, ou levam o texto para outro lugar
    func run(_ a: SelectionAction) {
        guard !working else { return }
        chosen = nil
        chosenAction = a
        result = ""
        failed = false
        let text = original
        switch a {
        case .explain, .document, .tests:
            working = true
            Task {
                do { result = Self.stripFences(try await AIText.ask(a.instruction, about: text)) } catch { failed = true }
                working = false
            }
        case .note:
            if let app = NSApp.delegate as? AppDelegate {
                let id = app.notes.create(text: text)
                HUD.show(icon: "note.text", color: .yellow, text: L("Nota criada"))
                cancel()
                app.openNote(id)
            }
        case .memory:
            MemoryStore.shared.add(text: text, origin: origin)
            cancel()
        case .reminder:
            working = true
            Task {
                // Título e data pela IA; sem data, o lembrete fica sem data
                let d = await SelectionEvents.draft(from: text)
                let p = QuickReminder.Parsed(title: d?.title ?? String(text.prefix(120)), due: d?.start, hasTime: d?.start != nil)
                working = false
                cancel()
                await QuickReminder.create(p)
            }
        case .event:
            working = true
            Task {
                let ok = await SelectionEvents.create(from: text)
                working = false
                if ok { cancel() } else { failed = true }
            }
        }
    }

    /// Tira a cerca de bloco de código (```swift … ```) que o modelo às vezes põe em volta
    static func stripFences(_ s: String) -> String {
        var lines = s.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Cola o texto novo no lugar da seleção e devolve o clipboard de antes
    func replace() {
        guard !result.isEmpty else { return }
        close()
        let pb = NSPasteboard.general
        pb.clearContents()
        // Marcado como passageiro: não entra no histórico do clipboard
        let item = NSPasteboardItem()
        item.setString(result, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pb.writeObjects([item])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ClipboardManager.postCommandV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.restoreClipboard() }
        }
    }

    func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
        close()
    }

    func cancel() {
        close()
        restoreClipboard()
    }

    private func close() { panel?.orderOut(nil) }

    private func restoreClipboard() {
        guard !savedClipboard.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(savedClipboard.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            return item
        })
    }

    static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var out: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { out[t] = d } }
            return out
        }
    }

    static func postCommand(_ key: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    /// Painel que não ativa o Menew: o app de onde veio o texto continua na frente para receber a colagem
    private func show() {
        let p = panel ?? {
            let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                             styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.contentView = NSHostingView(rootView: RewriterView(model: self))
            return p
        }()
        panel = p
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let v = screen?.visibleFrame ?? .zero
        let x = min(max(mouse.x - 220, v.minX + 8), v.maxX - 448)
        let y = min(max(mouse.y - 400, v.minY + 8), v.maxY - 388)
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.makeKeyAndOrderFront(nil)
    }
}

struct RewriterView: View {
    @ObservedObject var model: Rewriter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.and.outline").foregroundStyle(.pink)
                Text(L("Texto selecionado")).font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.working { ProgressView().controlSize(.small) }
            }
            Text(model.original).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
            if model.aiAvailable {
            FlowLayout(spacing: 6) {
                ForEach(Array(Rewriter.options.enumerated()), id: \.element) { i, a in
                    Button { model.choose(a) } label: {
                        Text(Self.short(a)).font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(model.chosen == a ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                    .disabled(model.working)
                }
            }
            }
            // Fazer algo com o texto
            FlowLayout(spacing: 6) {
                ForEach(SelectionAction.allCases.filter { model.aiAvailable || !$0.needsAI }, id: \.self) { a in
                    Button { model.run(a) } label: {
                        Label(a.title, systemImage: a.icon).font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(model.chosenAction == a ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.04)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.working)
                }
            }
            ScrollView {
                Text(model.failed ? L("A IA não conseguiu responder")
                     : model.chosen == nil && model.chosenAction == nil ? (model.aiAvailable ? L("Escolha como reescrever (ou aperte 1 a 6) ou o que fazer com o texto.") : L("Sem Apple Intelligence: dá para virar nota ou ir para a memória."))
                     : model.result.isEmpty ? L("Pensando…") : model.result)
                    .font(.system(size: 12.5)).lineSpacing(2).textSelection(.enabled)
                    .foregroundStyle(model.result.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .card(padding: 10)
            HStack {
                Spacer()
                PillButton(title: L("Cancelar"), icon: "xmark") { model.cancel() }.keyboardShortcut(.cancelAction)
                PillButton(title: L("Copiar"), icon: "doc.on.doc") { model.copyResult() }
                    .disabled(model.working || model.result.isEmpty)
                PillButton(title: L("Substituir"), icon: "arrow.turn.down.left", primary: true) { model.replace() }
                    .disabled(model.working || model.result.isEmpty || model.chosenAction == .explain || model.chosenAction == .tests)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14).padding(.top, 26).padding(.bottom, 12)
        .frame(width: 440, height: 380)
        .background(VisualEffect(material: .popover).ignoresSafeArea())
    }

    static func short(_ a: AIAction) -> String {
        switch a {
        case .fix: L("Corrigir")
        case .clearer: L("Mais claro")
        case .formal: L("Mais formal")
        case .friendly: L("Mais amigável")
        case .shorter: L("Mais curto")
        case .toEnglish: L("Em inglês")
        default: a.title
        }
    }
}

/// O que fazer com o texto selecionado, além de reescrever
enum SelectionAction: CaseIterable {
    case explain, document, tests, reminder, event, note, memory

    var title: String {
        switch self {
        case .explain: L("Explicar")
        case .document: L("Documentar código")
        case .tests: L("Gerar testes")
        case .reminder: L("Virar lembrete")
        case .event: L("Virar evento")
        case .note: L("Virar nota")
        case .memory: L("Guardar na memória")
        }
    }

    var icon: String {
        switch self {
        case .explain: "lightbulb"
        case .document: "text.badge.plus"
        case .tests: "checkmark.diamond"
        case .reminder: "checklist"
        case .event: "calendar.badge.plus"
        case .note: "note.text"
        case .memory: "brain.head.profile"
        }
    }

    var needsAI: Bool { ![.note, .memory].contains(self) }

    var instruction: String {
        switch self {
        case .explain: "Explain this in simple words, in a few sentences. If it is code, say what it does and point out any problem."
        case .document: "Return this code with clear documentation comments added in the language's usual style. Do not change the code itself."
        case .tests: "Write unit tests for this code, in the same language and the usual test framework for it. Return only the test code."
        default: ""
        }
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
@Generable
struct EventDraft {
    @Guide(description: "Short event title")
    var title: String
    @Guide(description: "Start as yyyy-MM-dd HH:mm, or empty if there is no date")
    var start: String
    @Guide(description: "Duration in minutes, 60 if not said")
    var minutes: Int
    @Guide(description: "Place or link, or empty")
    var location: String
}
#endif

import EventKit

/// Texto selecionado vira evento no Calendário: a IA acha título, data, duração e lugar
@MainActor
enum SelectionEvents {
    struct Draft { var title: String; var start: Date?; var minutes: Int; var location: String }

    /// Título, data, duração e lugar de um texto qualquer ("revisão com a Carla terça às 15h, pelo Meet")
    static func draft(from text: String) async -> Draft? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), AIText.unavailableReason == nil else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let session = LanguageModelSession(instructions: "Today is \(f.string(from: Date())) (\(Date().formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US"))))). Extract one event or task from the user's text. Write the title in the text's language.")
        guard let d = try? await session.respond(to: text, generating: EventDraft.self).content else { return nil }
        return Draft(title: d.title, start: f.date(from: d.start), minutes: d.minutes, location: d.location)
        #else
        return nil
        #endif
    }

    static func create(from text: String) async -> Bool {
        #if canImport(FoundationModels)
        guard let d = await draft(from: text), let start = d.start else {
            HUD.show(icon: "calendar.badge.exclamationmark", color: .orange, text: L("Não achei uma data no texto"), duration: 2.5)
            return false
        }
        let store = EKEventStore()
        let granted: Bool
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly: granted = true
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        default: granted = false
        }
        guard granted else {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Permita o Calendário em Ajustes do Sistema"), duration: 2.5)
            return false
        }
        let e = EKEvent(eventStore: store)
        e.title = d.title.isEmpty ? String(text.prefix(60)) : d.title
        e.startDate = start
        e.endDate = start.addingTimeInterval(Double(max(15, d.minutes)) * 60)
        if !d.location.isEmpty { e.location = d.location }
        e.notes = text
        e.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(e, span: .thisEvent, commit: true)
            HUD.show(icon: "calendar.badge.checkmark", color: .red, text: L("Evento criado: %@", start.formatted(date: .abbreviated, time: .shortened)))
            return true
        } catch {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para criar o evento"), duration: 2.5)
            return false
        }
        #else
        return false
        #endif
    }
}
