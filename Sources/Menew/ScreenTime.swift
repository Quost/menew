import AppKit
import SwiftUI

/// Tempo de tela, como o NotchTime: quanto tempo você passou em cada app, por dia, semana e mês, separado em
/// foco, neutro e distração. Conta só o app da frente e só enquanto você está usando o Mac (2 min sem mexer = pausa).
/// Começa desligado; tudo fica num arquivo no Mac e dá para apagar quando quiser.
@MainActor
final class ScreenTime: ObservableObject {
    static let shared = ScreenTime()
    static let key = "screenTimeOn"
    static let categoriesKey = "screenTimeCategories"

    enum Category: String, CaseIterable, Codable {
        case focus, neutral, distraction
        var title: String {
            switch self {
            case .focus: L("Foco")
            case .neutral: L("Neutro")
            case .distraction: L("Distração")
            }
        }
        var color: Color {
            switch self {
            case .focus: .teal
            case .neutral: .gray
            case .distraction: .orange
            }
        }
    }

    /// Segundos por app em cada hora do dia ("2026-11-01" → hora → bundle → segundos)
    struct Day: Codable {
        var hours: [Int: [String: Double]] = [:]
        var names: [String: String] = [:]
    }

    @Published private(set) var days: [String: Day] = [:]
    @Published var isOn = UserDefaults.standard.bool(forKey: ScreenTime.key)
    private var timer: Timer?
    private var url: URL?
    private var lastTick = Date()
    private var lastSave = Date()
    private var demo = false

    func load(dir: URL) {
        url = dir.appendingPathComponent("screen-time.json")
        if let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: Day].self, from: data) {
            days = saved
        }
        prune()
        refresh()
        // Ao sair do Menew, guarda o que ainda não foi salvo
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ScreenTime.shared.save() }
        }
    }

    func setOn(_ on: Bool) {
        isOn = on
        UserDefaults.standard.set(on, forKey: Self.key)
        refresh()
    }

    func refresh() {
        timer?.invalidate()
        timer = nil
        guard isOn, !demo else { return }
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated { ScreenTime.shared.tick() }
        }
    }

    /// A cada 15 s: soma o tempo ao app da frente, se você mexeu no Mac nos últimos 2 minutos
    private func tick(now: Date = Date()) {
        let elapsed = min(now.timeIntervalSince(lastTick), 30)
        lastTick = now
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard idle < 120, let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return }
        add(id, name: app.localizedName ?? id, seconds: elapsed, at: now)
        if now.timeIntervalSince(lastSave) > 300 { save() }
    }

    func add(_ id: String, name: String, seconds: Double, at date: Date) {
        let key = Self.dayKey(date)
        let hour = Calendar.current.component(.hour, from: date)
        var day = days[key] ?? Day()
        day.hours[hour, default: [:]][id, default: 0] += seconds
        day.names[id] = name
        days[key] = day
    }

    func save() {
        lastSave = Date()
        guard let url, !demo, let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func erase() {
        days = [:]
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func prune() {
        let cutoff = Self.dayKey(Date().addingTimeInterval(-40 * 86_400))
        days = days.filter { $0.key >= cutoff }
    }

    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "2026-11-02" → a data (meia-noite)
    static func date(fromKey key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    // MARK: Categorias

    private static let focusApps = ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.jetbrains", "com.figma.Desktop",
        "com.apple.iWork", "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.apple.Terminal", "com.googlecode.iterm2",
        "com.apple.Notes", "md.obsidian", "notion.id", "com.linear", "com.apple.mail", "com.microsoft.Outlook", "com.anthropic.claudefordesktop",
        "dev.warp", "com.sublimetext", "com.apple.Keynote", "com.apple.Pages", "com.apple.Numbers", "com.microsoft.teams", "us.zoom.xos"]
    private static let distractionApps = ["com.spotify.client", "com.apple.TV", "com.apple.Music", "com.netflix", "tv.twitch", "com.valvesoftware.steam",
        "com.hnc.Discord", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.facebook", "com.apple.MobileSMS", "com.tinyspeck.slackmacgap.games",
        "com.apple.news", "com.apple.Arcade"]

    func category(_ id: String) -> Category {
        if let raw = (UserDefaults.standard.dictionary(forKey: Self.categoriesKey) as? [String: String])?[id], let c = Category(rawValue: raw) { return c }
        if Self.focusApps.contains(where: { id.hasPrefix($0) }) { return .focus }
        if Self.distractionApps.contains(where: { id.hasPrefix($0) }) { return .distraction }
        return .neutral
    }

    func setCategory(_ c: Category, for id: String) {
        var map = UserDefaults.standard.dictionary(forKey: Self.categoriesKey) as? [String: String] ?? [:]
        map[id] = c.rawValue
        UserDefaults.standard.set(map, forKey: Self.categoriesKey)
        objectWillChange.send()
    }

    // MARK: Leitura

    enum Range: Int, CaseIterable {
        case day, week, month
        var title: String { switch self { case .day: L("Hoje"); case .week: L("7 dias"); case .month: L("30 dias") } }
        var count: Int { switch self { case .day: 1; case .week: 7; case .month: 30 } }
    }

    /// Os dias do período, do mais antigo ao de hoje
    func dayKeys(_ r: Range, now: Date = Date()) -> [String] {
        (0..<r.count).reversed().map { Self.dayKey(now.addingTimeInterval(-Double($0) * 86_400)) }
    }

    func totals(_ keys: [String]) -> [(id: String, name: String, seconds: Double)] {
        var sum: [String: Double] = [:], names: [String: String] = [:]
        for k in keys {
            guard let d = days[k] else { continue }
            for (_, apps) in d.hours { for (id, s) in apps { sum[id, default: 0] += s } }
            names.merge(d.names) { a, _ in a }
        }
        return sum.map { ($0.key, names[$0.key] ?? $0.key, $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    func byCategory(_ keys: [String]) -> [Category: Double] {
        var out: [Category: Double] = [:]
        for t in totals(keys) { out[category(t.id), default: 0] += t.seconds }
        return out
    }

    /// Para a linha do tempo de um dia: segundos por hora e categoria
    func hours(_ key: String) -> [Int: [Category: Double]] {
        var out: [Int: [Category: Double]] = [:]
        for (h, apps) in days[key]?.hours ?? [:] { for (id, s) in apps { out[h, default: [:]][category(id), default: 0] += s } }
        return out
    }

    func showDemo() {
        demo = true
        isOn = true
        let apps: [(String, String, [Int], Double)] = [
            ("com.apple.dt.Xcode", "Xcode", [9, 10, 11, 14, 15, 16], 2400), ("com.figma.Desktop", "Figma", [10, 15], 1500),
            ("com.apple.Safari", "Safari", [9, 12, 13, 17, 21], 1100), ("com.apple.mail", "Mail", [9, 13], 700),
            ("com.spotify.client", "Spotify", [12, 18, 22], 600), ("net.whatsapp.WhatsApp", "WhatsApp", [12, 19, 21, 22], 900),
        ]
        for back in 0..<30 {
            let base = Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(back) * 86_400))
            for (id, name, hrs, secs) in apps {
                for h in hrs where (back + h) % 5 != 0 {
                    add(id, name: name, seconds: secs * (0.6 + Double((back * 7 + h) % 5) / 10), at: base.addingTimeInterval(Double(h) * 3600 + 60))
                }
            }
        }
    }
}

/// Cartão "Tempo de tela" na aba Sistema
struct ScreenTimeCard: View {
    @ObservedObject var st = ScreenTime.shared
    @AppStorage("screenTimeRange") private var rangeRaw = 0
    private var range: ScreenTime.Range { ScreenTime.Range(rawValue: rangeRaw) ?? .day }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: L("Tempo de tela"), icon: "hourglass", color: .teal)
            if !st.isOn {
                Text(L("Veja quanto tempo você passa em cada app, separado em foco e distração. Fica só no seu Mac."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                PillButton(title: L("Ligar o tempo de tela"), icon: "play.fill", primary: true) { st.setOn(true) }
            } else {
                GlassSegmented(selection: $rangeRaw, options: ScreenTime.Range.allCases.map { .init(value: $0.rawValue, title: $0.title) })
                let keys = st.dayKeys(range)
                let totals = st.totals(keys)
                let cats = st.byCategory(keys)
                let total = cats.values.reduce(0, +)
                let perDay = range == .day ? total : total / Double(max(1, keys.filter { st.days[$0] != nil }.count))
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.format(perDay)).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(range == .day ? L("hoje") : L("média por dia")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                }
                if total > 0 {
                    // Barra de foco, neutro e distração
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            ForEach(ScreenTime.Category.allCases, id: \.self) { c in
                                let v = cats[c] ?? 0
                                if v > 0 { RoundedRectangle(cornerRadius: 3).fill(c.color).frame(width: max(3, g.size.width * v / total - 2)) }
                            }
                        }
                    }
                    .frame(height: 8)
                    HStack(spacing: 12) {
                        ForEach(ScreenTime.Category.allCases, id: \.self) { c in
                            HStack(spacing: 4) {
                                Circle().fill(c.color).frame(width: 7, height: 7)
                                Text("\(c.title) \(Self.format((cats[c] ?? 0) / (range == .day ? 1 : Double(max(1, keys.filter { st.days[$0] != nil }.count)))))")
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    if range == .day { dayTimeline(keys.last ?? "") } else { daysChart(keys) }
                    ForEach(totals.prefix(5), id: \.id) { t in
                        HStack(spacing: 8) {
                            Image(nsImage: Self.icon(t.id)).resizable().frame(width: 18, height: 18)
                            Text(t.name).font(.system(size: 12)).lineLimit(1)
                            Circle().fill(st.category(t.id).color).frame(width: 6, height: 6)
                            Spacer()
                            Text(Self.format(t.seconds / (range == .day ? 1 : Double(max(1, keys.filter { st.days[$0] != nil }.count)))))
                                .font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            ForEach(ScreenTime.Category.allCases, id: \.self) { c in
                                Button(L("Marcar como %@", c.title)) { st.setCategory(c, for: t.id) }
                            }
                        }
                    }
                    Text(L("Clique com o botão direito num app para mudar a categoria.")).font(.system(size: 10)).foregroundStyle(.tertiary)
                } else {
                    Text(L("Os números aparecem conforme você usa o Mac.")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(L("Desligar")) { st.setOn(false) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button(L("Apagar histórico")) { st.erase() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .card(padding: 14)
    }

    /// Hoje, hora a hora: cada coluna mostra foco, neutro e distração
    private func dayTimeline(_ key: String) -> some View {
        let hours = st.hours(key)
        return VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { h in
                    VStack(spacing: 0) {
                        ForEach(ScreenTime.Category.allCases.reversed(), id: \.self) { c in
                            Rectangle().fill(c.color).frame(height: 34 * min(1, (hours[h]?[c] ?? 0) / 3600))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 34, alignment: .bottom)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.04)))
                }
            }
            HStack { Text("0h"); Spacer(); Text("6h"); Spacer(); Text("12h"); Spacer(); Text("18h"); Spacer(); Text("24h") }
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    /// Semana ou mês: uma barra por dia
    private func daysChart(_ keys: [String]) -> some View {
        let maxDay = keys.map { st.byCategory([$0]).values.reduce(0, +) }.max() ?? 1
        return VStack(spacing: 3) {
            bars(keys, maxDay: maxDay)
            if keys.count <= 7 {
                HStack(spacing: 6) {
                    ForEach(keys, id: \.self) { k in
                        Text(Self.weekday(k)).font(.system(size: 9)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// "2026-11-01" → "dom."
    static func weekday(_ key: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key) else { return "" }
        return d.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))
    }

    private func bars(_ keys: [String], maxDay: Double) -> some View {
        HStack(alignment: .bottom, spacing: keys.count > 10 ? 2 : 6) {
            ForEach(keys, id: \.self) { k in
                let c = st.byCategory([k])
                VStack(spacing: 0) {
                    ForEach(ScreenTime.Category.allCases.reversed(), id: \.self) { cat in
                        Rectangle().fill(cat.color).frame(height: 44 * (c[cat] ?? 0) / max(maxDay, 1))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 44, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .frame(height: 44)
    }

    static func format(_ s: Double) -> String {
        let m = Int(s / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    static func icon(_ id: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
