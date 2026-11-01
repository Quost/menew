import AppKit
import EventKit

/// Lembretes rápidos pela paleta: "lembrar pagar boleto amanhã 9h" cria no app Lembretes, com a data entendida no texto
/// (o macOS reconhece datas em português, inglês, alemão, espanhol e chinês). Pede acesso aos Lembretes só no primeiro uso.
@MainActor
enum QuickReminder {
    private static let store = EKEventStore()
    static let prefixes = ["lembrar ", "lembrete ", "remind ", "reminder ", "erinnern ", "erinnerung ", "recordar ", "recordatorio ", "提醒 "]

    struct Parsed {
        let title: String
        let due: Date?
        let hasTime: Bool
    }

    /// Texto depois da palavra-chave: título e data
    nonisolated static func parse(_ text: String) -> Parsed? {
        var title = text.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        var due: Date?, hasTime = false
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let m = detector.matches(in: title, range: NSRange(title.startIndex..., in: title)).last,
           let r = Range(m.range, in: title), let date = m.date {
            let matched = String(title[r])
            due = date
            // "amanhã" sozinho vira o dia todo; "amanhã 9h", "at 9am", "um 9 Uhr" têm horário
            hasTime = matched.range(of: #"\d\s*(h|:|am|pm|uhr|点)|\b(às|as|at|um|a las)\s*\d"#, options: [.regularExpression, .caseInsensitive]) != nil
            title.removeSubrange(r)
            title = title.replacingOccurrences(of: #"\s+(às|as|at|on|em|no|na|um|am|a las|el)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            title = title.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        guard !title.isEmpty else { return nil }
        return Parsed(title: title.prefix(1).uppercased() + title.dropFirst(), due: due, hasTime: hasTime)
    }

    static func paletteItem(raw: String) -> PaletteItem? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let prefix = prefixes.first(where: { text.lowercased().hasPrefix($0) }),
              let p = parse(String(text.dropFirst(prefix.count))) else { return nil }
        let when = p.due.map { d in
            p.hasTime ? d.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute().locale(L10n.locale))
                : d.formatted(.dateTime.weekday(.abbreviated).day().month().locale(L10n.locale))
        }
        return PaletteItem(id: "reminder.new", kind: .calc, title: L("Lembrete: %@", p.title),
                           subtitle: when.map { L("No app Lembretes · %@", $0) } ?? L("No app Lembretes, sem data"),
                           keywords: text, icon: .symbol("checklist", .orange), remember: false) {
            Task { await create(p) }
        }
    }

    static func create(_ p: Parsed) async {
        let granted: Bool
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: granted = true
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            granted = (try? await store.requestFullAccessToReminders()) ?? false
        default: granted = false
        }
        guard granted else {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Permita os Lembretes em Ajustes do Sistema"), duration: 2.5)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
            return
        }
        let r = EKReminder(eventStore: store)
        r.title = p.title
        r.calendar = store.defaultCalendarForNewReminders()
        if let due = p.due {
            let parts: Set<Calendar.Component> = p.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            r.dueDateComponents = Calendar.current.dateComponents(parts, from: due)
            if p.hasTime { r.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        do {
            try store.save(r, commit: true)
            HUD.show(icon: "checklist", color: .orange, text: L("Lembrete criado"))
        } catch {
            HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: L("Não deu para criar o lembrete"), duration: 2.5)
        }
    }
}
