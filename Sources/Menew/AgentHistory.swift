import Foundation

/// O uso de um dia, somado por ferramenta, app, modelo e projeto. Os registros das ferramentas somem com o tempo
/// (o Claude Code apaga as conversas depois de 30 dias) e o Menew só lê o último mês a cada vez; estas somas ficam
/// guardadas no Mac (Application Support/Menew/agent-usage.json) para os gráficos de meses e anos.
struct UsageDay: Codable, Equatable {
    /// "2026-11-10", no fuso do Mac
    var day: String
    var agent: AgentKind
    var client: AgentClient
    var model: String
    var project: String
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    /// US$ pelos preços da API (só o Claude tem preço)
    var cost = 0.0
    var replies = 0

    var total: Int { input + output + cacheRead + cacheWrite }

    struct Key: Hashable { let day: String, agent: AgentKind, client: AgentClient, model: String, project: String }
    var key: Key { Key(day: day, agent: agent, client: client, model: model, project: project) }

    /// Quanto o cache economizou (como `AgentPricing.cacheSavings`)
    var savings: Double {
        guard agent == .claude, let p = AgentPricing.price(model) else { return 0 }
        return Double(cacheRead) * (p.input - p.cacheRead) / 1_000_000
    }

    // Chaves curtas: são milhares de linhas por ano
    enum CodingKeys: String, CodingKey {
        case day = "d", agent = "a", client = "c", model = "m", project = "p"
        case input = "i", output = "o", cacheRead = "r", cacheWrite = "w", cost = "$", replies = "n"
    }

    static func dayString(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ day: String, _ cal: Calendar) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}

/// O histórico inteiro: o arquivo guardado e as contas em cima dele
struct AgentUsageHistory: Codable, Equatable {
    var version = 1
    /// A primeira leitura (de tudo o que os registros ainda têm) já foi feita
    var backfilled = false
    var rows: [UsageDay] = []

    /// Soma as respostas por dia × ferramenta × app × modelo × projeto
    static func aggregate(_ records: [UsageRecord], calendar cal: Calendar = .current) -> [UsageDay] {
        var acc: [UsageDay.Key: UsageDay] = [:]
        for r in records {
            let d = UsageDay.dayString(r.date, cal)
            let k = UsageDay.Key(day: d, agent: r.agent, client: r.client, model: r.model, project: r.project)
            var row = acc[k] ?? UsageDay(day: d, agent: r.agent, client: r.client, model: r.model, project: r.project)
            row.input += r.input
            row.output += r.output
            row.cacheRead += r.cacheRead
            row.cacheWrite += r.cacheWrite5m + r.cacheWrite1h
            row.cost += AgentPricing.cost(r) ?? 0
            row.replies += 1
            acc[k] = row
        }
        return acc.values.sorted(by: Self.order)
    }

    /// Junta uma leitura dos registros. Os dias a partir de `coveredFrom` (começo de um dia) foram lidos por inteiro,
    /// então trocam o que estava guardado: ler de novo nunca conta duas vezes. Um dia de uma ferramenta só é trocado
    /// se não encolheu; se encolheu, os registros foram apagados e o guardado vale mais. Devolve se algo mudou.
    @discardableResult
    mutating func merge(_ records: [UsageRecord], coveredFrom: Date, calendar cal: Calendar = .current) -> Bool {
        let fresh = Self.aggregate(records.filter { $0.date >= coveredFrom }, calendar: cal)
        let first = coveredFrom == .distantPast ? "" : UsageDay.dayString(coveredFrom, cal)
        struct DayAgent: Hashable { let day: String, agent: AgentKind }
        var freshBy: [DayAgent: [UsageDay]] = [:]
        for r in fresh { freshBy[DayAgent(day: r.day, agent: r.agent), default: []].append(r) }
        var storedTotal: [DayAgent: Int] = [:]
        for r in rows where r.day >= first { storedTotal[DayAgent(day: r.day, agent: r.agent), default: 0] += r.total }

        var replace = Set<DayAgent>()
        for (k, list) in freshBy where list.reduce(0, { $0 + $1.total }) >= storedTotal[k, default: 0] {
            replace.insert(k)
        }
        guard !replace.isEmpty else { return false }
        var next = rows.filter { !($0.day >= first && replace.contains(DayAgent(day: $0.day, agent: $0.agent))) }
        for k in replace { next += freshBy[k] ?? [] }
        next.sort(by: Self.order)
        guard next != rows else { return false }
        rows = next
        return true
    }

    private static func order(_ a: UsageDay, _ b: UsageDay) -> Bool {
        if a.day != b.day { return a.day < b.day }
        if a.agent != b.agent { return a.agent.rawValue < b.agent.rawValue }
        if a.client != b.client { return a.client.rawValue < b.client.rawValue }
        if a.model != b.model { return a.model < b.model }
        return a.project < b.project
    }

    // MARK: Arquivo

    static var url: URL {
        AppData.dir.appendingPathComponent("agent-usage.json")
    }

    static func load(from url: URL = Self.url) -> AgentUsageHistory {
        guard let data = try? Data(contentsOf: url), let h = try? JSONDecoder().decode(AgentUsageHistory.self, from: data) else { return .init() }
        return h
    }

    func save(to url: URL = Self.url) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: Períodos e barras

/// Os períodos do gráfico de uso
enum UsageRange: String, CaseIterable, Identifiable {
    case today, week, month, quarter, year, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: L("Hoje")
        case .week: L("7 dias")
        case .month: L("30 dias")
        case .quarter: L("90 dias")
        case .year: L("12 meses")
        case .all: L("Tudo")
        }
    }

    var days: Int? {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .all: nil
        }
    }
}

/// Uma barra por dia até 90 dias; por semana em 12 meses; por mês além disso
enum UsageBucket: Equatable {
    case day, week, month

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    var title: String {
        switch self {
        case .day: L("Por dia")
        case .week: L("Por semana")
        case .month: L("Por mês")
        }
    }

    /// Pelo número de dias mostrados
    static func forSpan(days: Int) -> UsageBucket {
        days <= 90 ? .day : days <= 400 ? .week : .month
    }

    /// O começo da barra em que a data cai
    func start(of date: Date, _ cal: Calendar) -> Date {
        cal.dateInterval(of: component, for: date)?.start ?? cal.startOfDay(for: date)
    }
}

/// Uma barra: o começo do período, a ferramenta (nil = todas somadas) e os tokens
struct AgentUsageBar: Equatable {
    let start: Date
    let agent: AgentKind?
    let tokens: Int
}

struct UsageWindow: Equatable {
    /// Primeiro dia mostrado (começo de uma barra)
    let start: Date
    let bucket: UsageBucket
}

extension AgentUsageHistory {
    /// O período: de onde começa (alinhado ao começo de uma barra) e o tamanho das barras
    func window(_ range: UsageRange, now: Date = Date(), calendar cal: Calendar = .current) -> UsageWindow {
        let today = cal.startOfDay(for: now)
        let first: Date
        if let days = range.days {
            first = cal.date(byAdding: .day, value: -(days - 1), to: today)!
        } else {
            first = rows.first.flatMap { UsageDay.date($0.day, cal) }.map { min($0, today) } ?? today
        }
        let span = (cal.dateComponents([.day], from: first, to: today).day ?? 0) + 1
        let bucket = UsageBucket.forSpan(days: span)
        return UsageWindow(start: bucket.start(of: first, cal), bucket: bucket)
    }

    func rows(since start: Date, calendar cal: Calendar = .current) -> [UsageDay] {
        let first = UsageDay.dayString(start, cal)
        return rows.filter { $0.day >= first }
    }

    /// As barras do período, uma por período (e por ferramenta, se `byAgent`), com zeros onde não houve uso
    func bars(_ w: UsageWindow, byAgent: Bool, now: Date = Date(), calendar cal: Calendar = .current) -> [AgentUsageBar] {
        var dates: [String: Date] = [:]
        var sums: [Date: [AgentKind: Int]] = [:]
        for r in rows(since: w.start, calendar: cal) {
            guard let d = dates[r.day] ?? UsageDay.date(r.day, cal) else { continue }
            dates[r.day] = d
            sums[w.bucket.start(of: d, cal), default: [:]][r.agent, default: 0] += r.total
        }
        var out: [AgentUsageBar] = []
        var b = w.start
        let end = cal.startOfDay(for: now)
        while b <= end {
            let s = sums[b] ?? [:]
            if byAgent {
                out += AgentKind.allCases.map { AgentUsageBar(start: b, agent: $0, tokens: s[$0] ?? 0) }
            } else {
                out.append(AgentUsageBar(start: b, agent: nil, tokens: s.values.reduce(0, +)))
            }
            guard let next = cal.date(byAdding: w.bucket.component, value: 1, to: b) else { break }
            b = next
        }
        return out
    }

    struct Totals: Equatable { var tokens = 0; var cost = 0.0; var savings = 0.0; var replies = 0 }

    func totals(since start: Date, calendar cal: Calendar = .current) -> Totals {
        var t = Totals()
        for r in rows(since: start, calendar: cal) {
            t.tokens += r.total
            t.cost += r.cost
            t.savings += r.savings
            t.replies += r.replies
        }
        return t
    }

    /// Os maiores (por tokens) numa dimensão: modelo, projeto ou app
    func top(since start: Date, by key: (UsageDay) -> String, limit: Int = 5, calendar cal: Calendar = .current)
        -> [(name: String, agent: AgentKind, tokens: Int, cost: Double)] {
        var acc: [String: (AgentKind, Int, Double)] = [:]
        for r in rows(since: start, calendar: cal) {
            let k = key(r)
            let cur = acc[k] ?? (r.agent, 0, 0)
            acc[k] = (cur.0, cur.1 + r.total, cur.2 + r.cost)
        }
        return acc.sorted { $0.value.1 != $1.value.1 ? $0.value.1 > $1.value.1 : $0.key < $1.key }
            .prefix(limit).map { ($0.key, $0.value.0, $0.value.1, $0.value.2) }
    }
}
