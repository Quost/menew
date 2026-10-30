import AppKit
import SwiftUI

/// Transformações do texto do clipboard, usadas pela paleta ("maiúsculas", "json", "base64"…).
/// Funções puras: recebem o texto e devolvem o resultado, ou nil quando não dá (JSON inválido, Base64 quebrado).
enum TextTransform: String, CaseIterable {
    case upper, lower, title, sentence, noAccents, trim
    case sortLines, reverseLines, uniqueLines
    case jsonPretty, jsonMinify, base64Encode, base64Decode, urlEncode, urlDecode
    case count, camel, snake, kebab

    var title: String {
        switch self {
        case .upper: L("MAIÚSCULAS")
        case .lower: L("minúsculas")
        case .title: L("Primeira Letra Maiúscula")
        case .sentence: L("Só a primeira maiúscula")
        case .noAccents: L("Remover acentos")
        case .trim: L("Remover espaços extras")
        case .sortLines: L("Ordenar linhas")
        case .reverseLines: L("Inverter linhas")
        case .uniqueLines: L("Remover linhas repetidas")
        case .jsonPretty: L("Formatar JSON")
        case .jsonMinify: L("Compactar JSON")
        case .base64Encode: L("Codificar em Base64")
        case .base64Decode: L("Decodificar Base64")
        case .urlEncode: L("Codificar para URL")
        case .urlDecode: L("Decodificar URL")
        case .count: L("Contar caracteres e palavras")
        case .camel: L("camelCase")
        case .snake: L("snake_case")
        case .kebab: L("kebab-case")
        }
    }

    var icon: String {
        switch self {
        case .upper, .lower, .title, .sentence: "textformat.size"
        case .noAccents: "character"
        case .trim: "text.justify.left"
        case .sortLines: "arrow.up.arrow.down"
        case .reverseLines: "arrow.uturn.down"
        case .uniqueLines: "line.3.horizontal.decrease"
        case .jsonPretty, .jsonMinify: "curlybraces"
        case .base64Encode, .base64Decode: "lock.doc"
        case .urlEncode, .urlDecode: "link"
        case .count: "number"
        case .camel, .snake, .kebab: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Palavras para a busca, nos 5 idiomas (o título traduzido já entra na busca)
    var keywords: String {
        let common = "texto text transformar transform converter convert umwandeln transformar 转换 文本"
        let own = switch self {
        case .upper: "maiúsculas maiusculas upper uppercase caps großbuchstaben grossbuchstaben mayúsculas mayusculas 大写"
        case .lower: "minúsculas minusculas lower lowercase kleinbuchstaben minúsculas 小写"
        case .title: "título titulo title case capitalizar capitalize primeiras maiúsculas wortanfänge großschreibung tipo título 标题 首字母"
        case .sentence: "frase sentence case primeira maiúscula satz satzanfang oración oracion 句子 句首"
        case .noAccents: "acentos accents diacríticos diacritics remover remove akzente entfernen quitar tildes 重音 变音"
        case .trim: "espaços espacos whitespace trim spaces limpar clean leerzeichen bereinigen espacios limpiar 空格 空白"
        case .sortLines: "ordenar sort linhas lines alfabética alphabetical sortieren zeilen ordenar líneas lineas 排序 行"
        case .reverseLines: "inverter reverse linhas lines umkehren zeilen invertir líneas lineas 反转 行"
        case .uniqueLines: "repetidas duplicadas duplicates unique dedupe linhas lines doppelte zeilen duplicadas líneas 重复 去重"
        case .jsonPretty: "json formatar format pretty print beautify indentar formatieren formatear 格式化"
        case .jsonMinify: "json compactar minify compact minificar komprimieren compactar 压缩"
        case .base64Encode: "base64 codificar encode kodieren codificar 编码"
        case .base64Decode: "base64 decodificar decode dekodieren decodificar 解码"
        case .urlEncode: "url codificar encode percent escape kodieren codificar 编码 链接"
        case .urlDecode: "url decodificar decode percent unescape dekodieren decodificar 解码 链接"
        case .count: "contar count caracteres characters palavras words linhas lines zählen zeichen wörter contar palabras 统计 字数 字符"
        case .camel: "camel camelcase código code variável variable 驼峰"
        case .snake: "snake snakecase underline underscore código code variável variable 下划线"
        case .kebab: "kebab kebabcase hífen hyphen dash slug código code 连字符"
        }
        return own + " " + common
    }

    /// Mostra o resultado em vez de copiar
    var isInfo: Bool { self == .count }

    /// Quando `apply` devolve nil
    var failure: String {
        switch self {
        case .jsonPretty, .jsonMinify: L("JSON inválido")
        case .base64Decode: L("Não é Base64 válido")
        default: L("Não deu para transformar este texto")
        }
    }

    func apply(_ s: String) -> String? {
        switch self {
        case .upper: s.uppercased()
        case .lower: s.lowercased()
        case .title: s.capitalized(with: L10n.locale)
        case .sentence: Self.sentenceCase(s)
        case .noAccents: s.applyingTransform(.stripDiacritics, reverse: false)
        case .trim: Self.collapseWhitespace(s)
        case .sortLines: Self.mapLines(s) { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
        case .reverseLines: Self.mapLines(s) { $0.reversed() }
        case .uniqueLines: Self.mapLines(s) { lines in var seen = Set<String>(); return lines.filter { seen.insert($0).inserted } }
        case .jsonPretty: Self.json(s, [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        case .jsonMinify: Self.json(s, [.withoutEscapingSlashes])
        case .base64Encode: Data(s.utf8).base64EncodedString()
        case .base64Decode: Self.base64Decode(s)
        case .urlEncode: s.addingPercentEncoding(withAllowedCharacters: Self.unreserved)
        case .urlDecode: s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        case .count: Self.stats(s)
        case .camel: Self.identifiers(s) { w in
            w.enumerated().map { $0 == 0 ? $1.lowercased() : $1.prefix(1).uppercased() + $1.dropFirst().lowercased() }.joined()
        }
        case .snake: Self.identifiers(s) { $0.map { $0.lowercased() }.joined(separator: "_") }
        case .kebab: Self.identifiers(s) { $0.map { $0.lowercased() }.joined(separator: "-") }
        }
    }

    // MARK: Ajudantes

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Tudo minúsculo, com maiúscula no começo do texto e depois de . ! ? ou quebra de linha
    private static func sentenceCase(_ s: String) -> String {
        var out = ""
        var capitalize = true
        for ch in s.lowercased() {
            if capitalize, ch.isLetter {
                out += ch.uppercased()
                capitalize = false
            } else {
                out.append(ch)
            }
            if ".!?".contains(ch) || ch.isNewline { capitalize = true }
        }
        return out
    }

    /// Tira espaços das pontas de cada linha, junta espaços repetidos e deixa no máximo uma linha em branco seguida
    private static func collapseWhitespace(_ s: String) -> String {
        var out: [String] = []
        for line in s.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let clean = line.split { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }.joined(separator: " ")
            if clean.isEmpty, out.last?.isEmpty ?? true { continue }
            out.append(clean)
        }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    /// Aplica `f` às linhas, mantendo a quebra de linha do fim, se houver
    private static func mapLines(_ s: String, _ f: ([String]) -> [String]) -> String {
        var lines = s.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let trailing = lines.count > 1 && lines.last == ""
        if trailing { lines.removeLast() }
        return f(lines).joined(separator: "\n") + (trailing ? "\n" : "")
    }

    private static func json(_ s: String, _ options: JSONSerialization.WritingOptions) -> String? {
        let data = Data(s.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: options.union(.fragmentsAllowed)) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    /// Aceita também Base64 de URL (- e _) e sem o "=" do fim
    private static func base64Decode(_ s: String) -> String? {
        var b = String(s.filter { !$0.isWhitespace })
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard !b.isEmpty else { return nil }
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        guard let data = Data(base64Encoded: b) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func stats(_ s: String) -> String {
        var words = 0
        s.enumerateSubstrings(in: s.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        let lines = s.isEmpty ? 0 : s.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        return L(lines == 1 ? "%d caracteres · %d palavras · %d linha" : "%d caracteres · %d palavras · %d linhas", s.count, words, lines)
    }

    /// Quebra cada linha em palavras ("Olá mundo", "helloWorld", "HTTPServer", "foo-bar") e junta de novo com `join`
    private static func identifiers(_ s: String, _ join: ([String]) -> String) -> String {
        let plain = s.applyingTransform(.stripDiacritics, reverse: false) ?? s
        return mapLines(plain) { lines in
            lines.map { line in
                var words: [String] = []
                var current = ""
                let chars = Array(line)
                for (i, ch) in chars.enumerated() {
                    guard ch.isLetter || ch.isNumber else {
                        if !current.isEmpty { words.append(current); current = "" }
                        continue
                    }
                    if let prev = current.last, ch.isUppercase {
                        let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                        // "helloWorld" → hello World; "HTTPServer" → HTTP Server
                        if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextIsLower) {
                            words.append(current)
                            current = ""
                        }
                    }
                    current.append(ch)
                }
                if !current.isEmpty { words.append(current) }
                return join(words)
            }
        }
    }
}

// MARK: Paleta

extension TextTransform {
    /// Prévias só até aqui; acima disso o ↩ ainda transforma, mas a paleta não calcula nada enquanto você digita
    private static let previewLimit = 100_000
    @MainActor private static var cache: (change: Int, text: String?, previews: [TextTransform: String]) = (-1, nil, [:])

    /// O texto do clipboard agora (nil se não for texto, for um arquivo ou vier marcado como senha).
    /// Lê o clipboard só quando ele muda.
    @MainActor static func clipboardText() -> String? {
        let pb = NSPasteboard.general
        if cache.change != pb.changeCount {
            let types = pb.types ?? []
            let skip = types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            let text = skip ? nil : pb.string(forType: .string)
            cache = (pb.changeCount, text?.isEmpty == false ? text : nil, [:])
        }
        return cache.text
    }

    @MainActor private static func preview(_ t: TextTransform, _ text: String) -> String {
        if text == cache.text, let p = cache.previews[t] { return p }
        let p: String
        if text.utf8.count > previewLimit {
            p = L("Texto grande demais para a prévia")
        } else if let r = t.apply(text) {
            p = String(r.prefix(200)).split(whereSeparator: \.isNewline).joined(separator: " ⏎ ")
        } else {
            p = t.failure
        }
        if text == cache.text { cache.previews[t] = p }
        return p
    }

    /// "maiúsculas", "json", "base64": itens da paleta que transformam `text`.
    /// Só calcula a prévia dos itens que combinam com a busca (e guarda até o clipboard mudar).
    @MainActor static func paletteItems(text: String, query: String) -> [PaletteItem] {
        let q = PaletteSearch.fold(query.trimmingCharacters(in: .whitespaces))
        guard q.count >= 2, !text.isEmpty else { return [] }
        return allCases.compactMap { t in
            guard PaletteSearch.score(q, title: t.title, keywords: t.keywords) != nil else { return nil }
            return PaletteItem(id: "text.\(t.rawValue)", kind: .action, title: t.title, subtitle: preview(t, text),
                               keywords: t.keywords, icon: .symbol(t.icon, .purple), remember: false) {
                guard let result = t.apply(text) else {
                    HUD.show(icon: "exclamationmark.triangle.fill", color: .orange, text: t.failure)
                    return
                }
                if t.isInfo {
                    HUD.show(icon: t.icon, color: .purple, text: result, duration: 3)
                    return
                }
                // Entra no histórico pelo poll, como um texto copiado
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(result, forType: .string)
                HUD.show(icon: t.icon, color: .purple, text: L("Texto transformado"))
                guard UserDefaults.standard.bool(forKey: "autoPaste") else { return }
                guard AXIsProcessTrusted() else { ClipboardManager.requestAccessibility(); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { ClipboardManager.postCommandV() }
            }
        }
    }
}
