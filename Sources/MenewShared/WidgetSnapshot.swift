import Foundation

/// O que o Menew passa para os widgets: um arquivo pequeno no contêiner compartilhado, reescrito a cada minuto.
/// Os widgets só leem; nada sai do Mac.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Meeting: Codable, Equatable, Sendable {
        public var title: String
        public var start: Date
        public var end: Date
        public var hasLink: Bool
        public init(title: String, start: Date, end: Date, hasLink: Bool) {
            self.title = title; self.start = start; self.end = end; self.hasLink = hasLink
        }
    }

    public struct Countdown: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case timer, alarm, focus, rest }
        public var label: String
        public var start: Date
        public var end: Date
        public var kind: Kind
        public init(label: String, start: Date, end: Date, kind: Kind) {
            self.label = label; self.start = start; self.end = end; self.kind = kind
        }
    }

    public struct AppTime: Codable, Equatable, Sendable {
        public var name: String
        public var seconds: Double
        public init(name: String, seconds: Double) { self.name = name; self.seconds = seconds }
    }

    public var updated: Date
    /// Idioma da interface do Menew (en, pt, de, es, zh)
    public var lang: String
    public var cpu: Double
    /// CPU do último minuto, do mais antigo ao mais novo (0…1)
    public var cpuHistory: [Double]
    public var memUsed: UInt64
    public var memTotal: UInt64
    public var diskFree: Int64
    public var diskTotal: Int64
    public var battery: Int?
    public var charging: Bool
    public var meetingsOn: Bool
    public var meetings: [Meeting]
    public var countdowns: [Countdown]
    public var screenTimeOn: Bool
    /// Hoje: segundos em foco, neutro e distração
    public var screenFocus: Double
    public var screenNeutral: Double
    public var screenDistraction: Double
    public var screenTop: [AppTime]

    public init(updated: Date = Date(), lang: String = "en", cpu: Double = 0, cpuHistory: [Double] = [], memUsed: UInt64 = 0, memTotal: UInt64 = 0,
                diskFree: Int64 = 0, diskTotal: Int64 = 0, battery: Int? = nil, charging: Bool = false, meetingsOn: Bool = false,
                meetings: [Meeting] = [], countdowns: [Countdown] = [], screenTimeOn: Bool = false, screenFocus: Double = 0,
                screenNeutral: Double = 0, screenDistraction: Double = 0, screenTop: [AppTime] = []) {
        self.updated = updated; self.lang = lang; self.cpu = cpu; self.cpuHistory = cpuHistory; self.memUsed = memUsed; self.memTotal = memTotal
        self.diskFree = diskFree; self.diskTotal = diskTotal; self.battery = battery; self.charging = charging; self.meetingsOn = meetingsOn
        self.meetings = meetings; self.countdowns = countdowns; self.screenTimeOn = screenTimeOn; self.screenFocus = screenFocus
        self.screenNeutral = screenNeutral; self.screenDistraction = screenDistraction; self.screenTop = screenTop
    }

    public var memFraction: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) }
    public var diskFraction: Double { diskTotal == 0 ? 0 : 1 - Double(diskFree) / Double(diskTotal) }
    public var screenTotal: Double { screenFocus + screenNeutral + screenDistraction }

    /// Contêiner compartilhado entre o app e os widgets (o prefixo é o Team ID, como o macOS exige)
    public static let group = "9527N6XKKW.com.matheusquost.menew"

    public static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget.json")
    }

    public static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    public func save() {
        guard let url = Self.url else { return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? e.encode(self).write(to: url, options: .atomic)
    }

    /// Dados de exemplo para a galeria de widgets e as capturas de tela
    public static func demo(lang: String, now: Date = Date()) -> WidgetSnapshot {
        func t(_ k: String) -> String { WL.s(k, lang) }
        func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
        var s = WidgetSnapshot(updated: now, lang: lang)
        s.cpu = 0.23
        s.cpuHistory = (0..<60).map { i -> Double in
            let wave: Double = 0.12 * sin(Double(i) / 6)
            return 0.18 + wave + (i % 7 == 0 ? 0.15 : 0)
        }
        s.memUsed = 11_200_000_000; s.memTotal = 16_000_000_000
        s.diskFree = 182_000_000_000; s.diskTotal = 494_000_000_000
        s.battery = 82
        s.meetingsOn = true
        s.meetings = [Meeting(title: t("Alinhamento semanal"), start: at(14), end: at(44), hasLink: true),
                      Meeting(title: t("Revisão do design"), start: at(120), end: at(150), hasLink: true),
                      Meeting(title: t("Almoço com a equipe"), start: at(240), end: at(300), hasLink: false)]
        s.countdowns = [Countdown(label: t("Foco"), start: at(-7), end: at(18), kind: .focus),
                        Countdown(label: t("Chá"), start: at(-1), end: at(4.2), kind: .timer)]
        s.screenTimeOn = true
        s.screenFocus = 3 * 3600 + 25 * 60; s.screenNeutral = 58 * 60; s.screenDistraction = 41 * 60
        s.screenTop = [AppTime(name: "Xcode", seconds: 2 * 3600 + 5 * 60), AppTime(name: "Safari", seconds: 74 * 60), AppTime(name: "Slack", seconds: 38 * 60)]
        return s
    }
}

/// Os poucos textos dos widgets, nos 5 idiomas do Menew (o app tem a tabela grande; aqui não dá para usá-la)
public enum WL {
    /// Idioma do sistema, para a galeria de widgets (antes de o Menew escrever o arquivo)
    public static var system: String {
        for id in Locale.preferredLanguages {
            let code = String(id.prefix(2))
            if ["en", "pt", "de", "es", "zh"].contains(code) { return code }
        }
        return "en"
    }

    public static func s(_ key: String, _ lang: String) -> String {
        guard lang != "pt", let row = table[key] else { return key }
        let i = ["en": 0, "de": 1, "es": 2, "zh": 3][lang] ?? 0
        return row[i]
    }

    static let table: [String: [String]] = [
        "Sistema": ["System", "System", "Sistema", "系统"],
        "CPU, memória, disco e bateria.": ["CPU, memory, disk and battery.", "CPU, Speicher, Festplatte und Batterie.", "CPU, memoria, disco y batería.", "CPU、内存、磁盘和电池。"],
        "Memória": ["Memory", "Speicher", "Memoria", "内存"],
        "Disco": ["Disk", "Festplatte", "Disco", "磁盘"],
        "Bateria": ["Battery", "Batterie", "Batería", "电池"],
        "livres": ["free", "frei", "libres", "可用"],
        "carregando": ["charging", "lädt", "cargando", "充电中"],
        "último minuto": ["last minute", "letzte Minute", "último minuto", "最近一分钟"],
        "Reuniões": ["Meetings", "Meetings", "Reuniones", "会议"],
        "A próxima reunião e o resto do dia.": ["Your next meeting and the rest of the day.", "Das nächste Meeting und der Rest des Tages.", "La próxima reunión y el resto del día.", "下一个会议和今天剩下的安排。"],
        "Agora": ["Now", "Jetzt", "Ahora", "进行中"],
        "Próxima": ["Next", "Als Nächstes", "Siguiente", "下一个"],
        "Sem mais reuniões hoje": ["No more meetings today", "Heute keine Meetings mehr", "No hay más reuniones hoy", "今天没有更多会议"],
        "Ligue o calendário no Menew": ["Turn on the calendar in Menew", "Kalender in Menew einschalten", "Activa el calendario en Menew", "在 Menew 中打开日历"],
        "com link": ["with link", "mit Link", "con enlace", "有链接"],
        "Timers": ["Timers", "Timer", "Temporizadores", "计时器"],
        "Foco e timers contando ao vivo.": ["Focus and timers counting down live.", "Fokus und Timer, live heruntergezählt.", "Enfoque y temporizadores en tiempo real.", "专注和计时器实时倒计时。"],
        "Nenhum timer": ["No timers", "Keine Timer", "Ningún temporizador", "没有计时器"],
        "Digite “timer 10m” na paleta.": ["Type “timer 10m” in the palette.", "Tippe „timer 10m“ in die Palette.", "Escribe “timer 10m” en la paleta.", "在命令面板输入“timer 10m”。"],
        "Foco": ["Focus", "Fokus", "Enfoque", "专注"],
        "Pausa": ["Break", "Pause", "Descanso", "休息"],
        "Alarme": ["Alarm", "Wecker", "Alarma", "闹钟"],
        "Timer": ["Timer", "Timer", "Temporizador", "计时器"],
        "Tempo de tela": ["Screen time", "Bildschirmzeit", "Tiempo de pantalla", "屏幕使用时间"],
        "Quanto tempo você passou em cada app hoje.": ["How long you spent in each app today.", "Wie lange du heute in jeder App warst.", "Cuánto tiempo pasaste en cada app hoy.", "今天在每个 App 上花费的时间。"],
        "hoje": ["today", "heute", "hoy", "今天"],
        "foco": ["focus", "Fokus", "enfoque", "专注"],
        "neutro": ["neutral", "neutral", "neutro", "中性"],
        "distração": ["distraction", "Ablenkung", "distracción", "分心"],
        "Ligue o tempo de tela no Menew": ["Turn on screen time in Menew", "Bildschirmzeit in Menew einschalten", "Activa el tiempo de pantalla en Menew", "在 Menew 中打开屏幕使用时间"],
        "Abra o Menew": ["Open Menew", "Menew öffnen", "Abre Menew", "打开 Menew"],
        "Alinhamento semanal": ["Weekly sync", "Wöchentliches Abstimmungsmeeting", "Reunión semanal", "每周例会"],
        "Revisão do design": ["Design review", "Design-Review", "Revisión de diseño", "设计评审"],
        "Almoço com a equipe": ["Team lunch", "Teamessen", "Almuerzo con el equipo", "团队午餐"],
        "Chá": ["Tea", "Tee", "Té", "茶"],
    ]

    /// 3725 s → "1h 2min"; 300 → "5min"
    public static func duration(_ s: Double) -> String {
        let m = Int(s / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)min" : "\(m)min"
    }
}
