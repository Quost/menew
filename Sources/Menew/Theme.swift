import SwiftUI

enum Theme {
    static let indigo = Color(red: 0.36, green: 0.42, blue: 1.0)
    static let violet = Color(red: 0.62, green: 0.25, blue: 0.95)
    static let brand = LinearGradient(colors: [indigo, violet], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cpu = Color(red: 0.33, green: 0.47, blue: 1.0)
    static let memory = Color(red: 0.66, green: 0.35, blue: 0.98)
    static let disk = Color(red: 0.13, green: 0.71, blue: 0.75)
    static let battery = Color(red: 0.2, green: 0.78, blue: 0.45)
    static let download = Color(red: 0.2, green: 0.6, blue: 1.0)
    static let upload = Color(red: 0.95, green: 0.42, blue: 0.62)

    /// Mantém a cor da métrica e só esquenta quando o uso fica alto
    static func load(_ f: Double, base: Color) -> Color {
        f > 0.9 ? .red : f > 0.75 ? .orange : base
    }

    static let windowFill = Color(nsColor: .windowBackgroundColor)
    static let cardFill = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 1, alpha: 0.85)
    })
    static let cardStroke = Color.primary.opacity(0.08)
    /// No macOS 26+ o próprio popover é de vidro: o conteúdo fica transparente por cima dele
    static var popoverFill: Color {
        if #available(macOS 26, *), !flatGlass { return .clear }
        return windowFill
    }
    /// Ligado pelo modo captura (--snapshot)
    nonisolated(unsafe) static var flatGlass = false
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: 14)
    }
}

extension View {
    func card(padding: CGFloat = 12) -> some View { modifier(CardModifier(padding: padding)) }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    let icon: String
    var color: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 4)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, icon: String, color: Color = .secondary) {
        self.init(title: title, icon: icon, color: color) { EmptyView() }
    }
}

struct Ring: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.001), 1))
                .stroke(AngularGradient(colors: [color.opacity(0.65), color], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.6), value: fraction)
    }
}

struct UsageBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.5), value: fraction)
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    /// nil = normaliza pelo maior valor (útil para rede)
    var maxValue: Double? = 1

    var body: some View {
        GeometryReader { g in
            let top = maxValue ?? max(values.max() ?? 1, 1)
            let step = g.size.width / CGFloat(max(values.count - 1, 1))
            let pts = values.enumerated().map {
                CGPoint(x: CGFloat($0) * step, y: g.size.height * (1 - CGFloat(min($1 / top, 1))) )
            }
            ZStack {
                Path { p in
                    guard let f = pts.first, let l = pts.last else { return }
                    p.move(to: CGPoint(x: f.x, y: g.size.height))
                    smooth(pts, into: &p, startWithLine: true)
                    p.addLine(to: CGPoint(x: l.x, y: g.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.32), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in smooth(pts, into: &p, startWithLine: false) }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Curva suave passando pelos pontos (pontos médios como âncoras)
    private func smooth(_ pts: [CGPoint], into p: inout Path, startWithLine: Bool) {
        guard let first = pts.first else { return }
        startWithLine ? p.addLine(to: first) : p.move(to: first)
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i - 1])
        }
        if let last = pts.last { p.addLine(to: last) }
    }
}

struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

struct IconButton: View {
    let icon: String
    var help: String = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.1 : 0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Botão em pílula de vidro: o "primário" ganha a cor da marca
struct PillButton: View {
    let title: String
    var icon: String? = nil
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(primary ? Color.white : Color.primary)
            .contentShape(Capsule())
            .glass(in: Capsule(), tint: primary ? Theme.indigo : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

enum RelDate {
    private static let f: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
    static func string(_ d: Date) -> String {
        f.locale = L10n.locale
        return Date().timeIntervalSince(d) < 30 ? L("agora") : f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: Liquid Glass (macOS 26+), com material translúcido nas versões anteriores

/// O Liquid Glass não respeita o recorte da rolagem (os cards passam por cima do cabeçalho).
/// Dentro de ScrollView ele fica desligado e os cards usam um preenchimento comum.
private struct LiquidGlassAllowedKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var liquidGlassAllowed: Bool {
        get { self[LiquidGlassAllowedKey.self] }
        set { self[LiquidGlassAllowedKey.self] = newValue }
    }
}

private struct GlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.liquidGlassAllowed) private var allowed

    func body(content: Content) -> some View {
        if Theme.flatGlass || !allowed {
            // Capturas e conteúdo rolável: preenchimento equivalente, sem vidro
            content.background(shape.fill(tint ?? .clear)).background(shape.fill(Theme.cardFill))
                .overlay(shape.stroke(Theme.cardStroke, lineWidth: 0.5))
        } else if #available(macOS 26, *), let glassy = content.liquidGlass(in: shape, tint: tint, interactive: interactive) {
            glassy
        } else {
            content.background(shape.fill(.regularMaterial))
                .background(shape.fill(tint ?? .clear))
                .overlay(shape.stroke(Theme.cardStroke, lineWidth: 0.5))
        }
    }
}

extension View {
    func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    /// Só existe ao compilar com o SDK do macOS 26 (Xcode 26+); em Xcodes antigos cai no material
    @available(macOS 26, *)
    fileprivate func liquidGlass<S: Shape>(in shape: S, tint: Color?, interactive: Bool) -> AnyView? {
        #if compiler(>=6.2)
        AnyView(glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape))
        #else
        nil
        #endif
    }

    func glass(cornerRadius: CGFloat = 14, tint: Color? = nil, interactive: Bool = false) -> some View {
        glass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive)
    }

    /// Para o conteúdo de uma ScrollView
    func noLiquidGlass() -> some View { environment(\.liquidGlassAllowed, false) }
}

/// Agrupa vidros próximos para eles se fundirem como no sistema
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content
    @Environment(\.liquidGlassAllowed) private var allowed

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), allowed, !Theme.flatGlass {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: Controles de vidro compartilhados

/// Seletor em cápsula de vidro, com a opção escolhida destacada (abas, Histórico/Snippets, tema…)
struct GlassSegmented<V: Hashable>: View {
    struct Option {
        let value: V
        var title: String? = nil
        var icon: String? = nil
        var help: String? = nil
    }

    @Binding var selection: V
    let options: [Option]
    /// false = cada opção do tamanho do conteúdo (só ícones, por exemplo)
    var expand = true
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                let on = o.value == selection
                Button {
                    withAnimation(.spring(duration: 0.28)) { selection = o.value }
                } label: {
                    HStack(spacing: 5) {
                        if let icon = o.icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                        if let title = o.title { Text(title).font(.system(size: 11.5, weight: on ? .semibold : .medium)).lineLimit(1) }
                    }
                    .frame(maxWidth: expand ? .infinity : nil)
                    .padding(.horizontal, expand ? 0 : 10).padding(.vertical, 6)
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .background {
                        if on {
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "selected", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(o.help ?? "")
            }
        }
        .padding(3)
        .glass(in: Capsule())
    }
}

/// Ficha de filtro em vidro; ligada, fica com a cor da marca
struct GlassChip: View {
    var title: String? = nil
    var icon: String? = nil
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
                if let title { Text(title).lineLimit(1) }
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(on ? Color.white : Color.secondary)
            .contentShape(Capsule())
            .glass(in: Capsule(), tint: on ? Theme.indigo : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: on)
    }
}

/// Seção com título pequeno e as linhas dentro de um só cartão de vidro
struct GlassSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(title)
            VStack(spacing: 0) { content }
                .padding(.vertical, 3)
                .glass()
            if let footer {
                Text(footer).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
    }
}

/// Linha fina entre as linhas de uma seção
struct RowDivider: View {
    var inset: CGFloat = 12
    var body: some View {
        Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, inset)
    }
}

/// Linha de ajuste: título (e detalhe) à esquerda, controle à direita
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var icon: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5))
                if let detail { Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// Interruptor no padrão das linhas de ajuste
struct ToggleRow: View {
    let title: String
    var detail: String? = nil
    var icon: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, detail: detail, icon: icon) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// Menu de opções com o rótulo em cápsula de vidro (no lugar do popup clássico)
struct GlassMenu<V: Hashable>: View {
    @Binding var selection: V
    let options: [(value: V, title: String)]

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button { selection = options[i].value } label: {
                    if options[i].value == selection { Label(options[i].title, systemImage: "checkmark") } else { Text(options[i].title) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(options.first { $0.value == selection }?.title ?? "").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .contentShape(Capsule())
            .glass(in: Capsule(), interactive: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

extension View {
    /// Campo de texto em cápsula de vidro
    func glassField() -> some View {
        padding(.horizontal, 12).padding(.vertical, 7).glass(in: Capsule())
    }
}
