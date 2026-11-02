import AppKit
import SwiftUI

/// Os recursos de IA num lugar só (Ajustes → IA): o que cada um faz, como usar e um botão para desligar.
/// Desligado, ele some da paleta, dos atalhos e dos botões. Tudo roda no Mac.
@MainActor
enum AIFeature: String, CaseIterable, Identifiable {
    case agent, ask, textActions, screenAsk, rewrite, diagnosis, notes, memory, smartSearch, translate, transcribe
    var id: String { rawValue }

    var key: String { "ai.\(rawValue)" }
    var isOn: Bool { UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key) }

    /// Precisa da Apple Intelligence (os outros usam o tradutor, o reconhecimento de fala ou o modelo de palavras do macOS)
    var needsAppleIntelligence: Bool { ![.smartSearch, .translate, .transcribe].contains(self) }

    var icon: String {
        switch self {
        case .agent: "wand.and.sparkles"
        case .ask: "bubble.left.and.text.bubble.right"
        case .textActions: "text.badge.star"
        case .screenAsk: "text.bubble"
        case .rewrite: "pencil.and.outline"
        case .diagnosis: "stethoscope"
        case .notes: "note.text"
        case .memory: "brain.head.profile"
        case .smartSearch: "magnifyingglass"
        case .translate: "globe"
        case .transcribe: "waveform"
        }
    }

    var title: String {
        switch self {
        case .agent: L("Comandos em linguagem natural")
        case .ask: L("Perguntar à IA")
        case .textActions: L("Resumir e reescrever o texto copiado")
        case .screenAsk: L("Pergunte sobre a tela")
        case .rewrite: L("Reescrever texto selecionado")
        case .diagnosis: L("Explicar por que o Mac está lento")
        case .notes: L("Resumo e tarefas nas notas")
        case .memory: L("Título e etiquetas na memória")
        case .smartSearch: L("Busca inteligente no clipboard")
        case .translate: L("Traduzir o texto copiado")
        case .transcribe: L("Transcrever áudio e vídeo")
        }
    }

    /// Como usar, em uma linha
    var howTo: String {
        switch self {
        case .agent: L("Na paleta, comece com “faz”: “faz modo escuro e abre o Safari”.")
        case .ask: L("Na paleta, comece com “ia”: “ia como recuso uma reunião?”.")
        case .textActions: L("Copie um texto e digite “resumir” ou “formal” na paleta.")
        case .screenAsk: L("Na paleta ou em Ações: selecione uma área e pergunte.")
        case .rewrite: L("Selecione um texto em qualquer app e aperte %@.", Shortcut.load(HotKeyCenter.rewriteKey, default: .rewriteDefault).display)
        case .diagnosis: L("Aba Sistema → Por que meu Mac está lento?")
        case .notes: L("Numa nota, menu ⋯ → Resumir ou Extrair tarefas.")
        case .memory: L("Capture com %@: a IA dá título, resumo e etiquetas para achar depois.", Shortcut.load(MemoryStore.shortcutKey, default: .memoryDefault).display)
        case .smartSearch: L("No clipboard, busque “link do hotel de ontem”.")
        case .translate: L("Copie um texto e digite “traduzir” na paleta.")
        case .transcribe: L("Solte um áudio ou vídeo na estante e escolha Transcrever.")
        }
    }

    static func set(_ f: AIFeature, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: f.key)
        // O atalho global só fica registrado com o recurso ligado, para não roubar ⌃⌥⌘R de outros apps
        if f == .rewrite { HotKeyCenter.shared.register() }
    }
}

/// Ajustes → IA
struct AISettingsSection: View {
    @State private var states: [AIFeature: Bool] = Dictionary(uniqueKeysWithValues: AIFeature.allCases.map { ($0, $0.isOn) })

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSection(title: L("Apple Intelligence"), footer: L("A IA do Menew usa só o modelo que roda no próprio Mac. Nada é enviado para a internet.")) {
                if let reason = AIText.unavailableReason {
                    SettingRow(title: reason, icon: "exclamationmark.triangle.fill") {
                        PillButton(title: L("Abrir Ajustes")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                        }
                    }
                    .foregroundStyle(.orange)
                } else {
                    SettingRow(title: L("Ligada neste Mac"), icon: "checkmark.seal.fill") { EmptyView() }
                        .foregroundStyle(.green)
                }
            }
            AboutMeSection()
            GlassSection(title: L("Recursos"), footer: L("Desligado, o recurso some da paleta, dos atalhos e dos botões.")) {
                ForEach(Array(AIFeature.allCases.enumerated()), id: \.element) { i, f in
                    if i > 0 { RowDivider() }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: f.icon).font(.system(size: 12, weight: .medium)).foregroundStyle(.pink).frame(width: 18).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(f.title).font(.system(size: 13))
                                if !f.needsAppleIntelligence {
                                    Text(L("sem Apple Intelligence")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                                }
                            }
                            Text(f.howTo).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: Binding(get: { states[f] ?? true }, set: { states[f] = $0; AIFeature.set(f, $0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
    }
}
