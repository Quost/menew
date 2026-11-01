import AppKit

/// Timers e alarmes pela paleta: "timer 10m chá", "timer 1h30", "alarme 7:30 reunião". O mais próximo aparece na
/// barra de menus e, na hora, toca um som e chega um aviso. Ficam só na memória: fechar o Menew cancela.
@MainActor
final class TimerStore: ObservableObject {
    static let shared = TimerStore()

    struct Countdown: Identifiable {
        let id: UUID
        let label: String
        let end: Date
        let isAlarm: Bool
        let timer: Timer
    }

    @Published private(set) var active: [Countdown] = []
    var onChange: (() -> Void)?

    static let timerWords = ["timer", "temporizador", "cronometro", "cronômetro", "countdown", "contagem", "kurzzeitwecker", "计时"]
    static let alarmWords = ["alarme", "alarm", "despertador", "despertar", "wecker", "alarma", "闹钟"]

    func add(label: String, end: Date, isAlarm: Bool) {
        let id = UUID()
        let t = Timer(fire: end, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { TimerStore.shared.fire(id) }
        }
        RunLoop.main.add(t, forMode: .common)
        active.append(Countdown(id: id, label: label, end: end, isAlarm: isAlarm, timer: t))
        active.sort { $0.end < $1.end }
        onChange?()
        let when = end.formatted(.dateTime.hour().minute().locale(L10n.locale))
        HUD.show(icon: isAlarm ? "alarm.fill" : "timer", color: .orange,
                 text: isAlarm ? L("Alarme às %@", when) : L("Timer até %@", when))
    }

    private func fire(_ id: UUID) {
        guard let c = active.first(where: { $0.id == id }) else { return }
        active.removeAll { $0.id == id }
        onChange?()
        NSSound(named: "Glass")?.play()
        let title = c.isAlarm ? L("Alarme") : L("Timer terminou")
        Alerts.shared.notify(id: "timer.\(id)", title: c.label.isEmpty ? title : "\(title): \(c.label)",
                             body: c.isAlarm ? c.end.formatted(.dateTime.hour().minute().locale(L10n.locale)) : L("O tempo acabou."))
        HUD.show(icon: c.isAlarm ? "alarm.fill" : "timer", color: .orange, text: c.label.isEmpty ? title : c.label, duration: 3)
    }

    func cancel(_ id: UUID) {
        guard let c = active.first(where: { $0.id == id }) else { return }
        c.timer.invalidate()
        active.removeAll { $0.id == id }
        onChange?()
        HUD.show(icon: "xmark.circle.fill", color: .secondary, text: L("Timer cancelado"))
    }

    /// Mais próximo na barra de menus, como o foco: minutos, e segundos no último minuto
    var segment: StatusSegment? {
        guard let next = active.first else { return nil }
        let left = max(0, Int(next.end.timeIntervalSinceNow.rounded(.up)))
        if next.isAlarm, left >= 3600 { return .stat(L("ALARME"), next.end.formatted(.dateTime.hour().minute().locale(L10n.locale))) }
        let value = left >= 3600 ? "\(left / 3600)h\(String(format: "%02d", left % 3600 / 60))" : left >= 60 ? "\((left + 59) / 60)m" : "\(left)s"
        return .stat(next.isAlarm ? L("ALARME") : L("TIMER"), value)
    }

    // MARK: Paleta

    /// "10", "10m", "90s", "1h", "1h30", "1:30" → segundos
    nonisolated static func duration(_ s: String) -> TimeInterval? {
        let t = s.lowercased()
        if let n = Double(t) { return n * 60 }
        if t.hasSuffix("min"), let n = Double(t.dropLast(3)) { return n * 60 }
        if t.hasSuffix("m"), let n = Double(t.dropLast()) { return n * 60 }
        if t.hasSuffix("s"), let n = Double(t.dropLast()) { return n }
        if t.contains("h") {
            let parts = t.split(separator: "h", omittingEmptySubsequences: false)
            guard let h = Double(parts[0]) else { return nil }
            let m = parts.count > 1 && !parts[1].isEmpty ? Double(parts[1].replacingOccurrences(of: "m", with: "")) ?? -1 : 0
            return m < 0 ? nil : h * 3600 + m * 60
        }
        let hm = t.split(separator: ":")
        if hm.count == 2, let h = Double(hm[0]), let m = Double(hm[1]) { return h * 3600 + m * 60 }
        return nil
    }

    /// "7", "7h", "7:30", "7h30", "19:00", "7am", "7pm" → a próxima vez que esse horário acontece
    nonisolated static func alarmTime(_ s: String) -> Date? {
        var t = s.lowercased()
        var pm = false, am = false
        if t.hasSuffix("pm") { pm = true; t.removeLast(2) } else if t.hasSuffix("am") { am = true; t.removeLast(2) }
        let parts = t.replacingOccurrences(of: "h", with: ":").split(separator: ":", omittingEmptySubsequences: false)
        guard let first = parts.first, var h = Int(first), (0...23).contains(h) else { return nil }
        let m = parts.count > 1 && !parts[1].isEmpty ? Int(parts[1]) ?? -1 : 0
        guard (0..<60).contains(m) else { return nil }
        if pm, h < 12 { h += 12 }
        if am, h == 12 { h = 0 }
        return Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: h, minute: m, second: 0), matchingPolicy: .nextTime)
    }

    func paletteItems(raw: String) -> [PaletteItem] {
        let words = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        var out: [PaletteItem] = []
        if let first = words.first?.lowercased(), words.count >= 2 {
            let label = words.dropFirst(2).joined(separator: " ")
            if Self.timerWords.contains(PaletteSearch.fold(first)), let secs = Self.duration(words[1]), secs > 0, secs <= 24 * 3600 {
                let end = Date().addingTimeInterval(secs)
                let mins = Int(secs) / 60, rest = Int(secs) % 60
                let span = mins >= 60 ? "\(mins / 60) h \(mins % 60) min" : mins > 0 ? "\(mins) min" + (rest > 0 ? " \(rest) s" : "") : "\(rest) s"
                out.append(PaletteItem(id: "timer.new", kind: .calc, title: label.isEmpty ? L("Timer de %@", span) : L("Timer de %@: %@", span, label),
                                       subtitle: L("Termina às %@", end.formatted(.dateTime.hour().minute().locale(L10n.locale))),
                                       keywords: raw, icon: .symbol("timer", .orange), remember: false) {
                    TimerStore.shared.add(label: label, end: Date().addingTimeInterval(secs), isAlarm: false)
                })
            }
            if Self.alarmWords.contains(PaletteSearch.fold(first)), let end = Self.alarmTime(words[1]) {
                let when = end.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(L10n.locale))
                out.append(PaletteItem(id: "alarm.new", kind: .calc, title: label.isEmpty ? L("Alarme às %@", when) : L("Alarme às %@: %@", when, label),
                                       subtitle: L("Toca um som e avisa na hora"), keywords: raw,
                                       icon: .symbol("alarm.fill", .orange), remember: false) {
                    TimerStore.shared.add(label: label, end: end, isAlarm: true)
                })
            }
        }
        // Timers ligados: dá para cancelar procurando "timer" ou "alarme"
        let q = PaletteSearch.fold(raw.trimmingCharacters(in: .whitespaces))
        if q.count >= 3, (Self.timerWords + Self.alarmWords + ["cancelar", "cancel"]).contains(where: { $0.hasPrefix(q) || q.hasPrefix($0) }) {
            for c in active {
                let when = c.end.formatted(.dateTime.hour().minute().locale(L10n.locale))
                out.append(PaletteItem(id: "timer.cancel.\(c.id)", kind: .action, title: L("Cancelar %@ das %@", c.isAlarm ? L("alarme") : L("timer"), when),
                                       subtitle: c.label.isEmpty ? nil : c.label, keywords: raw,
                                       icon: .symbol("xmark.circle.fill", .gray), remember: false) { TimerStore.shared.cancel(c.id) })
            }
        }
        return out
    }
}
