import Foundation

/// Contas e conversões da paleta. Avaliador próprio (o NSExpression derruba o app com entrada inválida).
enum Calculator {
    struct Result: Equatable {
        let value: String      // o que aparece e vai para o clipboard
        let detail: String     // a conta entendida
    }

    /// nil quando o texto não é uma conta (um número sozinho também não é)
    static func evaluate(_ raw: String) -> Result? {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        if let r = percentOf(q) ?? convert(q) { return r }
        guard q.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^x×÷%()√!")) != nil
                || functions.keys.contains(where: { q.contains($0) }) || q.contains("pi") || q.contains("π") else { return nil }
        var p = Parser(q)
        guard let v = p.parse(), v.isFinite else { return nil }
        return Result(value: format(v), detail: raw.trimmingCharacters(in: .whitespaces))
    }

    // MARK: "20% de 340"

    private static func percentOf(_ q: String) -> Result? {
        let parts = q.components(separatedBy: " ").filter { !$0.isEmpty }
        guard parts.count >= 3, parts[0].hasSuffix("%"), ["de", "of", "von", "del", "的"].contains(parts[1]),
              let p = number(String(parts[0].dropLast())) else { return nil }
        var parser = Parser(parts.dropFirst(2).joined(separator: " "))
        guard let base = parser.parse() else { return nil }
        return Result(value: format(p / 100 * base), detail: q)
    }

    // MARK: Unidades

    private enum Dim { case length, mass, volume, data, time, speed, temperature, area }

    /// Fator para a unidade base de cada grandeza (metro, grama, litro, byte, segundo, m/s, m²)
    private static let units: [String: (Dim, Double, String)] = {
        var u: [String: (Dim, Double, String)] = [:]
        func add(_ names: [String], _ d: Dim, _ f: Double) { for n in names { u[n] = (d, f, names[0]) } }
        add(["mm", "milimetro", "milimetros"], .length, 0.001)
        add(["cm", "centimetro", "centimetros"], .length, 0.01)
        add(["m", "metro", "metros", "meter"], .length, 1)
        add(["km", "quilometro", "quilometros", "kilometer"], .length, 1000)
        add(["in", "pol", "polegada", "polegadas", "inch", "inches", "\""], .length, 0.0254)
        add(["ft", "pe", "pes", "feet", "foot"], .length, 0.3048)
        add(["yd", "jarda", "jardas", "yard", "yards"], .length, 0.9144)
        add(["mi", "milha", "milhas", "mile", "miles"], .length, 1609.344)
        add(["mg"], .mass, 0.001)
        add(["g", "grama", "gramas", "gram"], .mass, 1)
        add(["kg", "quilo", "quilos", "kilo"], .mass, 1000)
        add(["t", "ton", "tonelada", "toneladas"], .mass, 1_000_000)
        add(["oz", "onca", "ounce", "ounces"], .mass, 28.349523125)
        add(["lb", "lbs", "libra", "libras", "pound", "pounds"], .mass, 453.59237)
        add(["ml"], .volume, 0.001)
        add(["l", "litro", "litros", "liter", "liters"], .volume, 1)
        add(["gal", "galao", "galoes", "gallon", "gallons"], .volume, 3.785411784)
        add(["floz"], .volume, 0.0295735295625)
        add(["xicara", "xicaras", "cup", "cups"], .volume, 0.24)
        add(["b", "byte", "bytes"], .data, 1)
        add(["kb"], .data, 1e3)
        add(["mb"], .data, 1e6)
        add(["gb"], .data, 1e9)
        add(["tb"], .data, 1e12)
        add(["kib"], .data, 1024)
        add(["mib"], .data, 1_048_576)
        add(["gib"], .data, 1_073_741_824)
        add(["s", "seg", "segundo", "segundos", "sec", "second", "seconds"], .time, 1)
        add(["min", "minuto", "minutos", "minute", "minutes"], .time, 60)
        add(["h", "hora", "horas", "hour", "hours"], .time, 3600)
        add(["d", "dia", "dias", "day", "days"], .time, 86400)
        add(["sem", "semana", "semanas", "week", "weeks"], .time, 604_800)
        add(["km/h", "kmh"], .speed, 1 / 3.6)
        add(["m/s"], .speed, 1)
        add(["mph"], .speed, 0.44704)
        add(["kn", "no", "nos", "knot", "knots"], .speed, 0.514444)
        add(["m2", "m²"], .area, 1)
        add(["km2", "km²"], .area, 1e6)
        add(["ha", "hectare", "hectares"], .area, 10_000)
        add(["ft2", "ft²"], .area, 0.09290304)
        add(["acre", "acres"], .area, 4046.8564224)
        add(["c", "°c", "celsius"], .temperature, 0)
        add(["f", "°f", "fahrenheit"], .temperature, 0)
        add(["k", "kelvin"], .temperature, 0)
        return u
    }()

    private static let connectors: Set<String> = ["em", "para", "in", "to", "nach", "en", "a", "->", "→", "=", "转"]

    /// "5 km em mi", "72f to c", "1,5 gb em mb"
    private static func convert(_ q: String) -> Result? {
        guard let (value, from, to) = splitConversion(q),
              let f = units[from], let t = units[to], f.0 == t.0 else { return nil }
        let out: Double
        if f.0 == .temperature {
            let celsius: Double = switch f.2 { case "f": (value - 32) * 5 / 9; case "k": value - 273.15; default: value }
            out = switch t.2 { case "f": celsius * 9 / 5 + 32; case "k": celsius + 273.15; default: celsius }
        } else {
            out = value * f.1 / t.1
        }
        return Result(value: "\(format(out, digits: 4)) \(symbol(t))", detail: "\(format(value)) \(symbol(f))")
    }

    private static func symbol(_ u: (Dim, Double, String)) -> String {
        switch u.0 {
        case .temperature: "°" + u.2.uppercased()
        case .data: u.2.count == 3 ? u.2.prefix(1).uppercased() + "i" + u.2.suffix(1).uppercased() : u.2.uppercased()
        default: u.2
        }
    }

    /// (valor, unidade de origem, unidade de destino) de "5 km em mi" ou "5km mi"
    static func splitConversion(_ q: String) -> (Double, String, String)? {
        var words = q.components(separatedBy: " ").filter { !$0.isEmpty }
        // Número grudado na unidade: "5km"
        if let first = words.first, let i = first.firstIndex(where: { !($0.isNumber || $0 == "," || $0 == ".") }), i != first.startIndex {
            words.replaceSubrange(0...0, with: [String(first[..<i]), String(first[i...])])
        }
        // O conector fica entre as unidades ("10 cm in in": o segundo "in" é a unidade)
        if words.count == 4, connectors.contains(words[2]) { words.remove(at: 2) }
        guard words.count == 3, let v = number(words[0]) else { return nil }
        return (v, words[1], words[2])
    }

    // MARK: Moedas (cotação buscada só quando você pede)

    static let currencies: Set<String> = ["usd", "eur", "brl", "gbp", "jpy", "cny", "cad", "aud", "chf", "ars", "mxn",
                                          "clp", "cop", "inr", "krw", "sek", "nok", "dkk", "pln", "try", "zar", "nzd", "hkd", "sgd"]

    /// "100 usd em brl" → (100, "USD", "BRL")
    static func currencyQuery(_ q: String) -> (Double, String, String)? {
        guard let (v, from, to) = splitConversion(q.lowercased()), currencies.contains(from), currencies.contains(to), from != to else { return nil }
        return (v, from.uppercased(), to.uppercased())
    }

    private struct RateCache { let date: Date; let rate: Double }
    nonisolated(unsafe) private static var rates: [String: RateCache] = [:]

    static func cachedRate(_ from: String, _ to: String) -> Double? {
        guard let c = rates["\(from)\(to)"], Date().timeIntervalSince(c.date) < 6 * 3600 else { return nil }
        return c.rate
    }

    /// Cotação do Banco Central Europeu via frankfurter.app (sem conta nem chave)
    static func fetchRate(_ from: String, _ to: String) async -> Double? {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=\(from)&to=\(to)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rate = (json["rates"] as? [String: Double])?[to] else { return nil }
        rates["\(from)\(to)"] = RateCache(date: Date(), rate: rate)
        return rate
    }

    static func currencyText(_ value: Double, _ code: String) -> String {
        value.formatted(.currency(code: code).locale(L10n.locale))
    }

    // MARK: Números

    static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    /// Até 10 casas, sem zeros sobrando e sem separador de milhar (fácil de colar em qualquer lugar)
    static func format(_ v: Double, digits: Int = 10) -> String {
        if v != 0, abs(v) >= 1e15 || abs(v) < 1e-9 { return String(format: "%.6g", v) }
        return v.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never).locale(L10n.locale))
    }

    fileprivate static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "√": { $0.squareRoot() }, "raiz": { $0.squareRoot() },
        "sin": { sin($0) }, "sen": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
        "log": { log10($0) }, "ln": { log($0) }, "abs": { abs($0) }, "round": { $0.rounded() },
    ]
}

// MARK: Parser

/// expr = termo (+|- termo)* · termo = potência (*|/ potência)* · potência = unário (^ potência)?
private struct Parser {
    private let chars: [Character]
    private var i = 0

    init(_ s: String) {
        chars = Array(s.replacingOccurrences(of: " ", with: ""))
    }

    mutating func parse() -> Double? {
        guard let v = expr(), i == chars.count else { return nil }
        return v
    }

    private var peek: Character? { i < chars.count ? chars[i] : nil }

    private mutating func expr() -> Double? {
        guard var v = term() else { return nil }
        while let c = peek, c == "+" || c == "-" {
            i += 1
            let start = i
            guard let r = term() else { return nil }
            // "200 + 10%" = 220, como nas calculadoras
            let isPercent = i > start && chars[i - 1] == "%"
            let amount = isPercent ? v * r : r
            v = c == "+" ? v + amount : v - amount
        }
        return v
    }

    private mutating func term() -> Double? {
        guard var v = power() else { return nil }
        while let c = peek {
            if c == "*" || c == "×" || c == "x" {
                i += 1
                guard let r = power() else { return nil }
                v *= r
            } else if c == "/" || c == "÷" {
                i += 1
                guard let r = power() else { return nil }
                v /= r
            } else if c == "(" || c.isLetter || c == "√" { // "2(3+1)", "2pi"
                guard let r = power() else { return nil }
                v *= r
            } else {
                break
            }
        }
        return v
    }

    private mutating func power() -> Double? {
        guard let base = unary() else { return nil }
        if peek == "^" {
            i += 1
            guard let exp = power() else { return nil }
            return pow(base, exp)
        }
        return base
    }

    private mutating func unary() -> Double? {
        if peek == "-" { i += 1; return unary().map { -$0 } }
        if peek == "+" { i += 1; return unary() }
        return postfix()
    }

    private mutating func postfix() -> Double? {
        guard var v = primary() else { return nil }
        while let c = peek {
            if c == "%" { i += 1; v /= 100 }
            else if c == "!" {
                i += 1
                guard v >= 0, v <= 170, v == v.rounded() else { return nil }
                v = (1...max(Int(v), 1)).reduce(1.0) { $0 * Double($1) }
            } else { break }
        }
        return v
    }

    private mutating func primary() -> Double? {
        guard let c = peek else { return nil }
        if c == "(" {
            i += 1
            guard let v = expr(), peek == ")" else { return nil }
            i += 1
            return v
        }
        if c.isNumber || c == "." || c == "," {
            let start = i
            while let d = peek, d.isNumber || d == "." || d == "," { i += 1 }
            return Calculator.number(String(chars[start..<i]))
        }
        if c == "√" {
            i += 1
            return primary().map { $0.squareRoot() }
        }
        if c.isLetter || c == "π" {
            let start = i
            while let d = peek, d.isLetter || d == "π" { i += 1 }
            let name = String(chars[start..<i])
            if name == "pi" || name == "π" { return .pi }
            if name == "e" { return M_E }
            guard let f = Calculator.functions[name] else { return nil }
            guard let arg = primary() else { return nil }
            return f(arg)
        }
        return nil
    }
}
