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

    static let cardFill = Color.primary.opacity(0.045)
    static let cardStroke = Color.primary.opacity(0.07)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 0.5))
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

/// Botão em pílula: estilo "primário" usa o gradiente da marca
struct PillButton: View {
    let title: String
    var icon: String? = nil
    var primary = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background {
                if primary {
                    Capsule().fill(Theme.brand).opacity(hover ? 0.88 : 1)
                } else {
                    Capsule().fill(Color.primary.opacity(hover ? 0.11 : 0.07))
                }
            }
            .foregroundStyle(primary ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

enum RelDate {
    private static let f: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .short
        return f
    }()
    static func string(_ d: Date) -> String {
        Date().timeIntervalSince(d) < 30 ? "agora" : f.localizedString(for: d, relativeTo: Date())
    }
}
