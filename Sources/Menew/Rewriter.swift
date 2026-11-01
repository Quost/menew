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
    @Published var working = false
    @Published var failed = false
    private var panel: NSPanel?
    private var savedClipboard: [[NSPasteboard.PasteboardType: Data]] = []

    /// Copia a seleção do app da frente (⌘C) e abre as opções perto do mouse
    func start() {
        if let reason = AIText.unavailableReason {
            HUD.show(icon: "apple.intelligence", color: .orange, text: reason, duration: 2.5)
            return
        }
        guard AXIsProcessTrusted() else {
            HUD.show(icon: "hand.raised.fill", color: .orange, text: L("Libere o Menew em Acessibilidade"), duration: 2.5)
            return
        }
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
            failed = false
            show()
        }
    }

    func choose(_ action: AIAction) {
        guard !working else { return }
        chosen = action
        result = ""
        failed = false
        working = true
        Task {
            do { result = try await AIText.generate(action, original) } catch { failed = true }
            working = false
        }
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
            let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
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
        let x = min(max(mouse.x - 210, v.minX + 8), v.maxX - 428)
        let y = min(max(mouse.y - 350, v.minY + 8), v.maxY - 338)
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
                Text(L("Reescrever texto selecionado")).font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.working { ProgressView().controlSize(.small) }
            }
            Text(model.original).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
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
            ScrollView {
                Text(model.failed ? L("A IA não conseguiu responder")
                     : model.chosen == nil ? L("Escolha como reescrever (ou aperte 1 a 6).")
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
                    .disabled(model.working || model.result.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14).padding(.top, 26).padding(.bottom, 12)
        .frame(width: 420, height: 330)
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
