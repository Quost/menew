import SwiftUI

/// Relógios de outras cidades (aba Sistema) e conversão de horário na paleta: "15h sp em lisboa", "hora em tóquio".
@MainActor
final class WorldClock: ObservableObject {
    static let shared = WorldClock()
    static let key = "worldClocks"

    @Published private(set) var zones: [TimeZone] = []

    private init() {
        zones = (UserDefaults.standard.stringArray(forKey: Self.key) ?? []).compactMap(TimeZone.init(identifier:))
    }

    func add(_ tz: TimeZone) {
        guard !zones.contains(where: { $0.identifier == tz.identifier }) else { return }
        zones.append(tz)
        save()
    }

    func remove(_ tz: TimeZone) {
        zones.removeAll { $0.identifier == tz.identifier }
        save()
    }

    /// Para as capturas de tela
    func demo() {
        zones = ["Europe/Lisbon", "America/New_York", "Asia/Shanghai"].compactMap(TimeZone.init(identifier:))
    }

    private func save() { UserDefaults.standard.set(zones.map(\.identifier), forKey: Self.key) }

    // MARK: Cidades

    /// "America/Sao_Paulo" → "Sao Paulo"
    static func city(_ tz: TimeZone) -> String {
        // Nome traduzido quando a gente conhece ("Nova York", "Tóquio")
        displayNames[tz.identifier]
            ?? tz.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tz.identifier
    }

    /// "+4 h", "−3 h", "+5:30"
    static func offset(_ tz: TimeZone, at date: Date = Date(), from: TimeZone = .current) -> String {
        let diff = tz.secondsFromGMT(for: date) - from.secondsFromGMT(for: date)
        if diff == 0 { return L("mesma hora") }
        let sign = diff > 0 ? "+" : "−"
        let h = abs(diff) / 3600, m = abs(diff) % 3600 / 60
        return m == 0 ? "\(sign)\(h) h" : String(format: "%@%d:%02d", sign, h, m)
    }

    private static var displayNames: [String: String] { [
        "America/Sao_Paulo": "São Paulo", "America/New_York": L("Nova York"), "Asia/Tokyo": L("Tóquio"),
        "Europe/London": L("Londres"), "Europe/Lisbon": L("Lisboa"), "Asia/Shanghai": L("Xangai"),
        "Europe/Berlin": L("Berlim"), "America/Los_Angeles": "Los Angeles", "America/Mexico_City": L("Cidade do México"),
        "Asia/Kolkata": L("Índia"), "UTC": "UTC",
    ] }

    /// Apelidos e nomes em português, inglês, alemão, espanhol e chinês
    private static let aliases: [String: String] = [
        "sp": "America/Sao_Paulo", "sao paulo": "America/Sao_Paulo", "brasil": "America/Sao_Paulo", "brasilia": "America/Sao_Paulo",
        "rio": "America/Sao_Paulo", "brazil": "America/Sao_Paulo", "巴西": "America/Sao_Paulo",
        "ny": "America/New_York", "nyc": "America/New_York", "nova york": "America/New_York", "new york": "America/New_York", "纽约": "America/New_York",
        "sf": "America/Los_Angeles", "la": "America/Los_Angeles", "san francisco": "America/Los_Angeles", "california": "America/Los_Angeles",
        "londres": "Europe/London", "london": "Europe/London", "uk": "Europe/London", "伦敦": "Europe/London",
        "lisboa": "Europe/Lisbon", "lisbon": "Europe/Lisbon", "lissabon": "Europe/Lisbon", "portugal": "Europe/Lisbon",
        "berlim": "Europe/Berlin", "berlin": "Europe/Berlin", "alemanha": "Europe/Berlin", "germany": "Europe/Berlin", "deutschland": "Europe/Berlin",
        "madri": "Europe/Madrid", "madrid": "Europe/Madrid", "espanha": "Europe/Madrid", "paris": "Europe/Paris", "franca": "Europe/Paris",
        "toquio": "Asia/Tokyo", "tokyo": "Asia/Tokyo", "tokio": "Asia/Tokyo", "japao": "Asia/Tokyo", "japan": "Asia/Tokyo", "东京": "Asia/Tokyo",
        "xangai": "Asia/Shanghai", "shanghai": "Asia/Shanghai", "pequim": "Asia/Shanghai", "beijing": "Asia/Shanghai", "china": "Asia/Shanghai",
        "上海": "Asia/Shanghai", "北京": "Asia/Shanghai",
        "india": "Asia/Kolkata", "bangalore": "Asia/Kolkata", "dubai": "Asia/Dubai", "sydney": "Australia/Sydney", "sidney": "Australia/Sydney",
        "mexico": "America/Mexico_City", "cdmx": "America/Mexico_City", "buenos aires": "America/Argentina/Buenos_Aires",
        "chicago": "America/Chicago", "toronto": "America/Toronto", "singapura": "Asia/Singapore", "singapore": "Asia/Singapore",
        "utc": "UTC", "gmt": "UTC",
    ]

    /// Fuso de um nome digitado: apelido, cidade do banco de fusos ("denver", "auckland") ou "aqui"
    static func zone(_ text: String) -> TimeZone? {
        let q = PaletteSearch.fold(text.trimmingCharacters(in: .whitespaces)).replacingOccurrences(of: "_", with: " ")
        guard q.count >= 2 else { return nil }
        if ["aqui", "here", "hier", "aca", "local", "这里"].contains(q) { return .current }
        if let id = aliases[q] { return TimeZone(identifier: id) }
        let id = TimeZone.knownTimeZoneIdentifiers.first { id in
            let city = PaletteSearch.fold(String(id.split(separator: "/").last ?? "")).replacingOccurrences(of: "_", with: " ")
            return city == q || (q.count >= 4 && city.hasPrefix(q))
        }
        return id.flatMap(TimeZone.init(identifier:))
    }

    /// Cidades para escolher em Ajustes, a partir do que você digitou
    static func search(_ text: String) -> [TimeZone] {
        let q = PaletteSearch.fold(text.trimmingCharacters(in: .whitespaces))
        guard q.count >= 2 else { return [] }
        var out: [TimeZone] = []
        for (alias, id) in aliases where alias.hasPrefix(q) {
            if let tz = TimeZone(identifier: id), !out.contains(tz) { out.append(tz) }
        }
        for id in TimeZone.knownTimeZoneIdentifiers {
            let city = PaletteSearch.fold(String(id.split(separator: "/").last ?? "")).replacingOccurrences(of: "_", with: " ")
            if city.hasPrefix(q) || city.contains(" " + q), let tz = TimeZone(identifier: id), !out.contains(tz) { out.append(tz) }
        }
        return Array(out.prefix(6))
    }

    // MARK: Paleta

    /// "15h sp em lisboa", "15:30 em nova york", "3pm ny to london", "hora em tóquio", "lisboa"
    static func paletteQuery(_ q: String) -> (date: Date, from: TimeZone, to: TimeZone)? {
        let words = q.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        let joiners: Set<String> = ["em", "in", "to", "para", "pra", "nach", "en", "a", "→", "->", "到"]
        let hourWords: Set<String> = ["hora", "horas", "time", "uhrzeit", "zeit", "時間", "时间"]

        // Só a cidade ("lisboa") ou "hora em lisboa": horário de agora lá
        if let tz = zone(q), !q.contains(where: \.isNumber) { return (Date(), .current, tz) }
        if hourWords.contains(words[0]), words.count >= 3, joiners.contains(words[1]), let tz = zone(words[2...].joined(separator: " ")) {
            return (Date(), .current, tz)
        }

        // Começa com um horário
        guard let (h, m) = parseTime(words[0]) else { return nil }
        var rest = Array(words.dropFirst())
        if let first = rest.first, ["am", "pm"].contains(first) {
            rest.removeFirst()
            guard let (h2, m2) = parseTime(words[0] + first) else { return nil }
            return convert(h2, m2, rest)
        }
        return convert(h, m, rest)

        func convert(_ h: Int, _ m: Int, _ rest: [String]) -> (Date, TimeZone, TimeZone)? {
            guard let j = rest.firstIndex(where: { joiners.contains($0) }), j + 1 < rest.count,
                  let to = zone(rest[(j + 1)...].joined(separator: " ")) else { return nil }
            let fromText = rest[..<j].joined(separator: " ")
            let from = fromText.isEmpty ? TimeZone.current : (zone(fromText) ?? TimeZone.current)
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = from
            guard let date = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) else { return nil }
            return (date, from, to)
        }
    }

    /// "15h", "15:30", "15h30", "3pm", "9am"
    private static func parseTime(_ s: String) -> (Int, Int)? {
        var t = s.lowercased()
        var pm = false, am = false
        if t.hasSuffix("pm") { pm = true; t.removeLast(2) } else if t.hasSuffix("am") { am = true; t.removeLast(2) }
        let parts = t.replacingOccurrences(of: "h", with: ":").split(separator: ":", omittingEmptySubsequences: false)
        guard let first = parts.first, let h0 = Int(first), (0...23).contains(h0) else { return nil }
        let m = parts.count > 1 && !parts[1].isEmpty ? Int(parts[1]) ?? -1 : 0
        guard (0..<60).contains(m) else { return nil }
        // Um número sozinho só vale como horário com "h" ou am/pm, para não confundir com contas
        guard s.contains("h") || s.contains(":") || pm || am else { return nil }
        var h = h0
        if pm, h < 12 { h += 12 }
        if am, h == 12 { h = 0 }
        return (h, m)
    }

    static func time(_ date: Date, in tz: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute().locale(L10n.locale)
        style.timeZone = tz
        return date.formatted(style)
    }

    /// "amanhã", "ontem" ou nada, comparando o dia lá com o daqui
    static func dayNote(_ date: Date, in tz: TimeZone, from: TimeZone = .current) -> String? {
        var a = Calendar(identifier: .gregorian), b = Calendar(identifier: .gregorian)
        a.timeZone = tz
        b.timeZone = from
        let d1 = a.dateComponents([.year, .month, .day], from: date), d2 = b.dateComponents([.year, .month, .day], from: date)
        guard let x = a.date(from: d1), let y = a.date(from: d2), x != y else { return nil }
        return x > y ? L("amanhã") : L("ontem")
    }
}

/// Cartão "Relógios" no topo da aba Sistema
struct WorldClockCard: View {
    @ObservedObject var clock = WorldClock.shared

    var body: some View {
        if !clock.zones.isEmpty {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                HStack(spacing: 0) {
                    ForEach(clock.zones, id: \.identifier) { tz in
                        VStack(spacing: 2) {
                            Text(WorldClock.time(ctx.date, in: tz))
                                .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(WorldClock.city(tz)).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Text([WorldClock.offset(tz, at: ctx.date), WorldClock.dayNote(ctx.date, in: tz)].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .card(padding: 12)
            }
        }
    }
}

/// Ajustes → Relógios: adicionar e tirar cidades
struct WorldClockSettings: View {
    @ObservedObject var clock = WorldClock.shared
    @State private var query = ""

    var body: some View {
        GlassSection(title: L("Relógios"), footer: L("Aparecem no topo da aba Sistema. Na paleta, digite “15h em Lisboa” ou “hora em Tóquio”.")) {
            ForEach(clock.zones, id: \.identifier) { tz in
                SettingRow(title: WorldClock.city(tz), detail: WorldClock.offset(tz)) {
                    Button { clock.remove(tz) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(L("Remover"))
                }
                RowDivider()
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField(L("Adicionar cidade…"), text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12.5))
                ForEach(WorldClock.search(query), id: \.identifier) { tz in
                    Button {
                        clock.add(tz)
                        query = ""
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                            Text(WorldClock.city(tz)).font(.system(size: 12))
                            Text(tz.identifier).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            Spacer()
                            Text(WorldClock.offset(tz)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}
