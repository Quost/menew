import AppKit
import SwiftUI

/// Fila de colagem: ligada, tudo que você copia entra na fila, e cada ⌘V cola o próximo, na ordem em que foi copiado.
/// Só escuta o ⌘V (sem mexer nele) enquanto a fila está ligada; precisa da permissão de Acessibilidade.
@MainActor
final class PasteQueue: ObservableObject {
    static let shared = PasteQueue()

    @Published private(set) var isOn = false
    @Published private(set) var items: [ClipItem] = []
    /// Para a barra de menus mostrar a contagem na hora
    var onChange: (() -> Void)?

    private weak var clipboard: ClipboardManager?
    private var monitor: Any?
    private var advancing = false

    func attach(_ clipboard: ClipboardManager) { self.clipboard = clipboard }

    func toggle() { isOn ? stop() : start() }

    func start() {
        guard !isOn else { return }
        guard AXIsProcessTrusted() else { ClipboardManager.requestAccessibility(); return }
        isOn = true
        items = []
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            // ⌘V puro (sem ⇧⌥⌃): o app da frente acabou de colar o primeiro da fila
            guard e.keyCode == 9, e.modifierFlags.intersection([.command, .shift, .option, .control]) == .command else { return }
            MainActor.assumeIsolated { self?.pasted() }
        }
        HUD.show(icon: "list.number", color: .purple, text: L("Fila de colagem ligada"), duration: 1.6)
        onChange?()
    }

    func stop() {
        guard isOn else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isOn = false
        items = []
        onChange?()
    }

    /// Algo novo foi copiado (pelo poll do clipboard)
    func captured(_ item: ClipItem) {
        guard isOn else { return }
        items.append(item)
        // O clipboard fica sempre com o primeiro da fila, para o ⌘V colar na ordem
        if items.count > 1 { writeHead() }
        HUD.show(icon: "list.number", color: .purple, text: L("Na fila: %d", items.count))
        onChange?()
    }

    /// Pelo menu de contexto do histórico
    func add(_ item: ClipItem) {
        start()
        guard isOn else { return }
        items.append(item)
        writeHead()
        HUD.show(icon: "list.number", color: .purple, text: L("Na fila: %d", items.count))
        onChange?()
    }

    func remove(_ item: ClipItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: i)
        if i == 0, !items.isEmpty { writeHead() }
        if items.isEmpty { stop() } else { onChange?() }
    }

    private func pasted() {
        guard isOn, !items.isEmpty, !advancing else { return }
        advancing = true
        // Tempo para o app ler o clipboard antes de trocar pelo próximo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            advancing = false
            guard isOn, !items.isEmpty else { return }
            items.removeFirst()
            if items.isEmpty {
                stop()
                HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Fila concluída"))
            } else {
                writeHead()
                onChange?()
            }
        }
    }

    private func writeHead() {
        guard let first = items.first, let clipboard else { return }
        clipboard.write(first)
        clipboard.ignoreCurrentChange()
    }

    var segment: StatusSegment? {
        isOn ? .stat(L("FILA"), "\(items.count)") : nil
    }
}

/// Faixa da fila no topo do histórico
struct PasteQueueBanner: View {
    @ObservedObject var queue = PasteQueue.shared

    var body: some View {
        if queue.isOn {
            HStack(spacing: 10) {
                Image(systemName: "list.number")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.purple)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.purple.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(queue.items.isEmpty ? L("Fila de colagem") : L("Fila de colagem · %d", queue.items.count))
                        .font(.system(size: 12, weight: .semibold))
                    Text(queue.items.first.map { L("Próximo ⌘V: %@", $0.preview) } ?? L("Copie os itens na ordem em que vai colar"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                PillButton(title: L("Parar"), icon: "stop.fill") { queue.stop() }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glass()
        }
    }
}

/// Botão da fila ao lado da busca
struct PasteQueueButton: View {
    @ObservedObject var queue = PasteQueue.shared

    var body: some View {
        Button { queue.toggle() } label: {
            Image(systemName: "list.number").font(.system(size: 12, weight: queue.isOn ? .semibold : .regular))
                .foregroundStyle(queue.isOn ? AnyShapeStyle(Color.purple) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.borderless)
        .help(queue.isOn ? L("Parar a fila de colagem") : L("Fila de colagem: copie vários itens e cole um por um com ⌘V"))
        .accessibilityLabel(L("Fila de colagem"))
    }
}
