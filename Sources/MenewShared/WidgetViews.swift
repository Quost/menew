import SwiftUI

/// Os desenhos dos widgets. Ficam aqui (e não no widget) para o app também renderizar nas capturas de tela.
public enum WidgetSize: Sendable { case small, medium }

private func bytes(_ v: Int64) -> String { ByteCountFormatter.string(fromByteCount: v, countStyle: .file) }

private func clock(_ d: Date, _ lang: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: ["en": "en_US", "pt": "pt_BR", "de": "de_DE", "es": "es_ES", "zh": "zh_CN"][lang] ?? "en_US")
    f.setLocalizedDateFormatFromTemplate("jmm")
    return f.string(from: d)
}

/// Cor de um uso: verde, laranja, vermelho
private func usageColor(_ v: Double) -> Color { v > 0.85 ? .red : v > 0.65 ? .orange : .green }

private struct Header: View {
    let icon: String
    let title: String
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct Bar: View {
    let value: Double
    let color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color.gradient).frame(width: max(4, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 5)
    }
}

// MARK: Sistema

public struct SystemWidgetView: View {
    let s: WidgetSnapshot
    let size: WidgetSize
    public init(_ s: WidgetSnapshot, size: WidgetSize) { self.s = s; self.size = size }

    public var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Header(icon: "cpu", title: WL.s("Sistema", s.lang), color: .blue)
                row("CPU", "\(Int((s.cpu * 100).rounded()))%", s.cpu, usageColor(s.cpu))
                row(WL.s("Memória", s.lang), "\(Int((s.memFraction * 100).rounded()))%", s.memFraction, usageColor(s.memFraction))
                row(WL.s("Disco", s.lang), "\(bytes(s.diskFree)) \(WL.s("livres", s.lang))", s.diskFraction, usageColor(s.diskFraction))
                if let b = s.battery {
                    row(WL.s("Bateria", s.lang), s.charging ? "\(b)% ⚡︎" : "\(b)%", Double(b) / 100, b <= 20 ? .red : .green)
                }
            }
            if size == .medium {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU · \(WL.s("último minuto", s.lang))").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Spark(values: s.cpuHistory).frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String, _ fraction: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                Text(value).font(.system(size: 11, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
            Bar(value: fraction, color: color)
        }
    }
}

private struct Spark: View {
    let values: [Double]
    var body: some View {
        GeometryReader { g in
            let v = values.isEmpty ? [0] : values
            let step = g.size.width / CGFloat(max(1, v.count - 1))
            let pts = v.enumerated().map { CGPoint(x: CGFloat($0.offset) * step, y: g.size.height * (1 - CGFloat(min(1, max(0, $0.element))))) }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: g.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: g.size.width, y: g.size.height))
                }
                .fill(LinearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                Path { p in p.addLines(pts) }.stroke(.blue, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: Reuniões

public struct MeetingsWidgetView: View {
    let s: WidgetSnapshot
    let size: WidgetSize
    let now: Date
    public init(_ s: WidgetSnapshot, size: WidgetSize, now: Date = Date()) { self.s = s; self.size = size; self.now = now }

    private var upcoming: [WidgetSnapshot.Meeting] { s.meetings.filter { $0.end > now } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(icon: "calendar", title: WL.s("Reuniões", s.lang), color: .red)
            if !s.meetingsOn {
                Spacer(minLength: 0)
                Text(WL.s("Ligue o calendário no Menew", s.lang)).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if let first = upcoming.first {
                let live = first.start <= now
                Text(live ? WL.s("Agora", s.lang) : WL.s("Próxima", s.lang)).font(.system(size: 10, weight: .semibold)).foregroundStyle(live ? .green : .orange)
                Text(first.title).font(.system(size: 14, weight: .semibold)).lineLimit(size == .small ? 2 : 1)
                Text("\(clock(first.start, s.lang))–\(clock(first.end, s.lang))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                if !live, first.start.timeIntervalSince(now) < 3600 {
                    // Contagem ao vivo até começar (o widget atualiza sozinho, sem gastar a cota)
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.system(size: 10))
                        Text(timerInterval: now...first.start, countsDown: true).monospacedDigit()
                    }
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                }
                if size == .medium {
                    Divider().padding(.vertical, 2)
                    ForEach(Array(upcoming.dropFirst().prefix(2).enumerated()), id: \.offset) { _, m in
                        HStack(spacing: 6) {
                            Capsule().fill(.red.opacity(0.7)).frame(width: 3, height: 14)
                            Text(clock(m.start, s.lang)).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                            Text(m.title).font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 0)
                            if m.hasLink { Image(systemName: "video.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(.green)
                Text(WL.s("Sem mais reuniões hoje", s.lang)).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Timers

public struct TimersWidgetView: View {
    let s: WidgetSnapshot
    let size: WidgetSize
    let now: Date
    public init(_ s: WidgetSnapshot, size: WidgetSize, now: Date = Date()) { self.s = s; self.size = size; self.now = now }

    public var body: some View {
        let list = s.countdowns.filter { $0.end > now }
        VStack(alignment: .leading, spacing: 8) {
            Header(icon: "timer", title: WL.s("Timers", s.lang), color: .orange)
            if list.isEmpty {
                Spacer(minLength: 0)
                Text(WL.s("Nenhum timer", s.lang)).font(.system(size: 13, weight: .semibold))
                Text(WL.s("Digite “timer 10m” na paleta.", s.lang)).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(list.prefix(size == .small ? 2 : 3).enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: icon(c.kind)).font(.system(size: 10, weight: .semibold)).foregroundStyle(color(c.kind))
                            Text(c.label.isEmpty ? name(c.kind) : c.label).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            if size == .medium {
                                Text(timerInterval: c.start...c.end, countsDown: true).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                    .multilineTextAlignment(.trailing).frame(width: 70, alignment: .trailing)
                            }
                        }
                        if size == .small {
                            Text(timerInterval: c.start...c.end, countsDown: true).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                        }
                        ProgressView(timerInterval: c.start...c.end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                            .progressViewStyle(.linear).tint(color(c.kind)).controlSize(.small)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func icon(_ k: WidgetSnapshot.Countdown.Kind) -> String {
        switch k { case .focus: "scope"; case .rest: "cup.and.saucer.fill"; case .alarm: "alarm.fill"; case .timer: "hourglass" }
    }
    private func color(_ k: WidgetSnapshot.Countdown.Kind) -> Color {
        switch k { case .focus: .orange; case .rest: .green; case .alarm: .pink; case .timer: .blue }
    }
    private func name(_ k: WidgetSnapshot.Countdown.Kind) -> String {
        switch k { case .focus: WL.s("Foco", s.lang); case .rest: WL.s("Pausa", s.lang); case .alarm: WL.s("Alarme", s.lang); case .timer: WL.s("Timer", s.lang) }
    }
}

// MARK: Tempo de tela

public struct ScreenTimeWidgetView: View {
    let s: WidgetSnapshot
    let size: WidgetSize
    public init(_ s: WidgetSnapshot, size: WidgetSize) { self.s = s; self.size = size }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Header(icon: "hourglass", title: WL.s("Tempo de tela", s.lang), color: .indigo)
            if !s.screenTimeOn {
                Spacer(minLength: 0)
                Text(WL.s("Ligue o tempo de tela no Menew", s.lang)).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(WL.duration(s.screenTotal)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    Text(WL.s("hoje", s.lang)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    let total = max(1, s.screenTotal)
                    HStack(spacing: 2) {
                        Capsule().fill(.green).frame(width: g.size.width * s.screenFocus / total)
                        Capsule().fill(.gray.opacity(0.6)).frame(width: g.size.width * s.screenNeutral / total)
                        Capsule().fill(.orange).frame(width: g.size.width * s.screenDistraction / total)
                    }
                }
                .frame(height: 6)
                HStack(spacing: 8) {
                    legend(.green, WL.s("foco", s.lang), s.screenFocus)
                    if size == .medium {
                        legend(.gray, WL.s("neutro", s.lang), s.screenNeutral)
                        legend(.orange, WL.s("distração", s.lang), s.screenDistraction)
                    }
                }
                ForEach(Array(s.screenTop.prefix(size == .small ? 1 : 3).enumerated()), id: \.offset) { _, a in
                    HStack {
                        Text(a.name).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(WL.duration(a.seconds)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func legend(_ c: Color, _ t: String, _ v: Double) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text("\(t) \(WL.duration(v))").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
