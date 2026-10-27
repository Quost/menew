import SwiftUI

// MARK: Ações

/// Em cima, controles que ligam e desligam (sempre mostrando o estado atual do Mac);
/// embaixo, ações de um toque, cada uma dizendo o que faz.
struct ActionsView: View {
    @ObservedObject var tb: Toolbox
    @ObservedObject var cleaning: CleaningController
    let clipboard: ClipboardManager
    var openCleaner: () -> Void

    init(tb: Toolbox, clipboard: ClipboardManager, openCleaner: @escaping () -> Void) {
        self.tb = tb
        self.cleaning = tb.cleaning
        self.clipboard = clipboard
        self.openCleaner = openCleaner
    }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section(L("Controles")) {
                    VStack(spacing: 0) {
                        ControlRow(icon: tb.darkMode ? "moon.fill" : "sun.max.fill", color: tb.darkMode ? .indigo : .orange,
                                   title: L("Modo escuro"), state: tb.darkMode ? L("Ligado") : L("Desligado"),
                                   help: L("Troca a aparência de todo o macOS entre claro e escuro."),
                                   isOn: Binding(get: { tb.darkMode }, set: { _ in tb.toggleDarkMode() }))
                        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
                        ControlRow(icon: "cup.and.saucer.fill", color: .orange, title: L("Manter acordado"),
                                   state: awakeState, help: L("Impede que a tela apague e o Mac durma."),
                                   isOn: Binding(get: { tb.keepAwake }, set: { tb.setKeepAwake($0) })) {
                            Menu {
                                ForEach([30, 60, 120, 240], id: \.self) { m in
                                    Button(m < 60 ? L("%d minutos", m) : (m == 60 ? L("1 hora") : L("%d horas", m / 60))) {
                                        tb.setKeepAwake(true, minutes: m)
                                    }
                                }
                                Divider()
                                Button(L("Até eu desligar")) { tb.setKeepAwake(true) }
                            } label: {
                                Image(systemName: "timer").font(.system(size: 12, weight: .semibold))
                            }
                            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                            .help(L("Manter acordado por um tempo"))
                        }
                        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
                        ControlRow(icon: tb.hiddenFiles ? "eye.fill" : "eye.slash.fill", color: .blue,
                                   title: L("Arquivos ocultos"), state: tb.hiddenFiles ? L("Aparecem no Finder") : L("Escondidos no Finder"),
                                   help: L("Mostra arquivos que começam com ponto, como .git e .env. O Finder reinicia."),
                                   isOn: Binding(get: { tb.hiddenFiles }, set: { _ in tb.toggleHiddenFiles() }))
                        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
                        ControlRow(icon: "menubar.dock.rectangle", color: .teal,
                                   title: L("Ícones da mesa"), state: tb.desktopIconsHidden ? L("Escondidos") : L("Aparecem"),
                                   help: L("Esconde tudo da mesa, bom para gravar a tela ou apresentar. Os arquivos continuam lá."),
                                   isOn: Binding(get: { !tb.desktopIconsHidden }, set: { _ in tb.toggleDesktopIcons() }))
                    }
                    .padding(.vertical, 4)
                    .glass()
                }

                section(L("Limpeza")) {
                    GlassGroup {
                        LazyVGrid(columns: cols, spacing: 8) {
                            ActionTile(icon: "sparkles", color: .blue, title: L("Liberar espaço"), subtitle: L("caches e lixo"),
                                       help: L("Encontra caches, logs e arquivos grandes. Você revisa antes de apagar."), action: openCleaner)
                            ActionTile(icon: "keyboard", color: .teal, title: L("Limpar teclado"),
                                       subtitle: cleaning.keyboardLocked ? L("travado") : L("trava por 2 min"),
                                       help: L("Bloqueia todas as teclas por 2 minutos para você limpar. Destrava com um clique."),
                                       on: cleaning.keyboardLocked) {
                                if !cleaning.lockKeyboard() { tb.show(L("Libere o Menew em Acessibilidade")) }
                            }
                            ActionTile(icon: "sparkles.tv", color: .cyan, title: L("Limpar tela"), subtitle: L("tela preta"),
                                       help: L("Deixa todas as telas pretas para ver manchas. Dois cliques para sair.")) {
                                cleaning.blackScreen()
                            }
                        }
                    }
                }

                section(L("Atalhos")) {
                    GlassGroup {
                        LazyVGrid(columns: cols, spacing: 8) {
                            ActionTile(icon: "camera.viewfinder", color: .pink, title: L("Print"), subtitle: L("vai pro clipboard"),
                                       help: L("Selecione uma área da tela. A imagem vai para o clipboard e aparece no histórico.")) {
                                tb.screenshotToClipboard()
                            }
                            ActionTile(icon: "eyedropper.halffull", color: Theme.violet, title: L("Conta-gotas"), subtitle: L("copia o hex"),
                                       help: L("Clique em qualquer ponto da tela para copiar a cor em hexadecimal.")) {
                                tb.pickColor(clipboard: clipboard)
                            }
                            ActionTile(icon: "textformat", color: .brown, title: L("Limpar formatação"), subtitle: L("do texto copiado"),
                                       help: L("Tira fonte, cor e links do texto copiado. Cole como texto simples.")) {
                                tb.plainTextClipboard()
                            }
                            ActionTile(icon: "lock.fill", color: .gray, title: L("Bloquear tela"), subtitle: L("pede a senha"),
                                       help: L("Apaga a tela na hora. Para voltar, use Touch ID ou sua senha.")) { tb.lockScreen() }
                            ActionTile(icon: "eject.fill", color: .mint, title: L("Ejetar discos"),
                                       subtitle: tb.ejectableCount == 0 ? L("nenhum conectado") : L("%d conectado(s)", tb.ejectableCount),
                                       help: L("Ejeta com segurança todos os discos externos e pendrives."),
                                       disabled: tb.ejectableCount == 0) { tb.ejectAll() }
                            ActionTile(icon: "trash", color: .red, title: L("Esvaziar lixeira"), subtitle: L("pede confirmação"),
                                       help: L("Apaga para sempre o que está na Lixeira. Pergunta antes.")) { tb.emptyTrash() }
                        }
                    }
                }

                HStack(spacing: 8) {
                    AppPill(icon: "chart.bar.xaxis", title: L("Monitor de Atividade")) {
                        tb.open("/System/Applications/Utilities/Activity Monitor.app")
                    }
                    AppPill(icon: "terminal.fill", title: L("Terminal")) {
                        tb.open("/System/Applications/Utilities/Terminal.app")
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .noLiquidGlass()
        .scrollIndicators(.never)
        .onAppear { tb.refresh() }
    }

    private var awakeState: String {
        guard tb.keepAwake else { return L("Desligado") }
        guard let until = tb.awakeUntil else { return L("Até você desligar") }
        return L("Até %@", until.formatted(.dateTime.hour().minute().locale(L10n.locale)))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            content()
        }
    }
}

/// Linha com ícone, nome, estado atual por extenso e um interruptor
struct ControlRow<Extra: View>: View {
    let icon: String
    let color: Color
    let title: String
    let state: String
    let help: String
    @Binding var isOn: Bool
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isOn ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.15))))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(state).font(.system(size: 11)).foregroundStyle(isOn ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 6)
            extra.foregroundStyle(.secondary)
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .help(help)
        .animation(.spring(duration: 0.3), value: isOn)
    }
}

extension ControlRow where Extra == EmptyView {
    init(icon: String, color: Color, title: String, state: String, help: String, isOn: Binding<Bool>) {
        self.init(icon: icon, color: color, title: title, state: state, help: help, isOn: isOn) { EmptyView() }
    }
}

/// Ação de um toque: ícone, nome e o que acontece, em vidro
struct ActionTile: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    var help: String = ""
    var on = false
    var disabled = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(color.gradient))
                    .shadow(color: color.opacity(0.35), radius: hover ? 6 : 3, y: 2)
                    .scaleEffect(hover && !disabled ? 1.06 : 1)
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(on ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 92)
            .contentShape(Rectangle())
            .glass(tint: on ? color.opacity(0.25) : nil, interactive: !disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hover = $0 }
        .help(help)
        .animation(.spring(duration: 0.25), value: hover)
        .animation(.spring(duration: 0.25), value: on)
    }
}

struct AppPill: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
            .glass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .help(L("Abrir %@", title))
    }
}
