import Foundation
import NaturalLanguage

/// Busca pelo sentido no histórico do clipboard: "o link do hotel de ontem", "aquele erro do xcode".
/// Entende palavras de data (hoje, ontem, esta semana) e de tipo (link, imagem, arquivo) e acha textos parecidos
/// pela raiz das palavras ("erro" acha "error") e por sinônimos do modelo de palavras do próprio macOS (Natural Language).
/// Não precisa de Apple Intelligence e nada sai do Mac.
@MainActor
enum SmartClipSearch {
    struct Parsed: Equatable {
        var since: Date?
        var until: Date?
        var kind: ClipItem.Kind?
        var onlyLinks = false
        var words: String
    }

    private static let today = ["hoje", "today", "heute", "hoy", "今天"]
    private static let yesterday = ["ontem", "yesterday", "gestern", "ayer", "昨天"]
    private static let week = ["semana", "week", "woche", "本周"]
    private static let links = ["link", "links", "url", "site", "enlace", "链接"]
    private static let images = ["imagem", "imagens", "image", "images", "foto", "print", "screenshot", "captura", "bild", "imagen", "图片"]
    private static let files = ["arquivo", "arquivos", "file", "files", "datei", "archivo", "文件"]
    /// Palavras que não ajudam na busca ("o", "de", "que eu copiei")
    private static let filler: Set<String> = ["o", "a", "os", "as", "do", "da", "de", "dos", "das", "que", "eu", "um", "uma", "aquele", "aquela",
        "copiei", "copiado", "the", "that", "i", "copied", "from", "of", "a", "an", "der", "die", "das", "den", "ich", "el", "la", "los", "las",
        "que", "copié", "esta", "this", "last", "passada", "dieser", "diese"]

    static func parse(_ query: String, now: Date = Date()) -> Parsed {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        var p = Parsed(words: "")
        var rest: [String] = []
        for raw in query.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            let w = String(raw)
            if today.contains(w) { p.since = start }
            else if yesterday.contains(w) { p.since = cal.date(byAdding: .day, value: -1, to: start); p.until = start }
            else if week.contains(w) { p.since = cal.date(byAdding: .day, value: -7, to: start) }
            else if links.contains(w) { p.onlyLinks = true }
            else if images.contains(w) { p.kind = .image }
            else if files.contains(w) { p.kind = .file }
            else if !filler.contains(w) { rest.append(w) }
        }
        p.words = rest.joined(separator: " ")
        return p
    }

    /// Só vale a pena com mais de uma palavra ou com data/tipo ("link de ontem")
    static func applies(_ query: String) -> Bool {
        let p = parse(query)
        return p.since != nil || p.kind != nil || p.onlyLinks || query.split(separator: " ").count >= 2
    }

    private static var cache: (query: String, count: Int, ids: [UUID])?

    /// Itens a mais, além dos que já batem pelo texto, do mais parecido ao menos
    static func extra(_ query: String, in base: [ClipItem], excluding exact: Set<UUID>) -> [ClipItem] {
        guard applies(query) else { return [] }
        if let c = cache, c.query == query, c.count == base.count {
            let byID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return c.ids.compactMap { byID[$0] }
        }
        let p = parse(query)
        var pool = base.filter { !exact.contains($0.id) }
        if let since = p.since { pool = pool.filter { $0.date >= since } }
        if let until = p.until { pool = pool.filter { $0.date < until } }
        if let kind = p.kind { pool = pool.filter { $0.kind == kind } }
        if p.onlyLinks { pool = pool.filter { $0.url != nil } }
        var result: [ClipItem]
        if p.words.isEmpty {
            // Só data ou tipo ("imagens de hoje"): tudo o que bate, do mais novo
            result = pool
        } else {
            result = rank(p.words, pool)
            // Com data ou tipo, quem bate por palavra solta também entra (o sentido sozinho é exigente)
            if p.since != nil || p.kind != nil || p.onlyLinks {
                let loose = pool.filter { item in
                    p.words.split(separator: " ").contains { w in text(item).range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                }
                result = loose + result.filter { r in !loose.contains { $0.id == r.id } }
            }
        }
        result = Array(result.prefix(20))
        cache = (query, base.count, result.map(\.id))
        return result
    }

    private static func text(_ item: ClipItem) -> String {
        [item.text, item.ocrText, item.sourceApp].compactMap { $0 }.joined(separator: " ")
    }

    /// Palavras sem acento e em minúsculas ("Compilação" → "compilacao"); quebra também camelCase
    static func tokens(_ text: String) -> [String] {
        let spaced = text.replacingOccurrences(of: #"([a-z])([A-Z])"#, with: "$1 $2", options: .regularExpression)
        return PaletteSearch.fold(spaced).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 2 }
    }

    /// Mesma raiz: as 4 ou 5 primeiras letras ("erro" ~ "error", "compilacao" ~ "compile")
    static func sameRoot(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let n = min(5, min(a.count, b.count))
        return n >= 4 && a.prefix(n) == b.prefix(n)
    }

    /// Cada palavra da busca precisa aparecer no item (pela raiz) ou ter um sinônimo próximo nele
    private static func rank(_ words: String, _ pool: [ClipItem]) -> [ClipItem] {
        let query = tokens(words)
        guard !query.isEmpty else { return [] }
        let lang = NLLanguageRecognizer.dominantLanguage(for: words) ?? .english
        let wordModel = NLEmbedding.wordEmbedding(for: lang)
        var scored: [(ClipItem, Double)] = []
        for item in pool.prefix(400) {
            let itemWords = Array(Set(tokens(String(text(item).prefix(400)))).prefix(80))
            var total = 0.0
            for w in query {
                if itemWords.contains(where: { sameRoot(w, $0) }) { total += 1; continue }
                // Sinônimo: distância do cosseno no modelo de palavras (0 = igual, 2 = oposto)
                if let wordModel {
                    let best = itemWords.map { 1 - wordModel.distance(between: w, and: $0) }.max() ?? 0
                    if best >= synonym { total += 0.7 }
                }
            }
            let score = total / Double(query.count)
            if score >= threshold { scored.append((item, score)) }
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    static let threshold = 0.5
    static let synonym = 0.55
}
