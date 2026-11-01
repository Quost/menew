import AppKit

/// Emoji e símbolos na paleta: "emoji foguete" ou ":rocket" para emoji; "seta", "grau", "euro", "check" para símbolos.
/// ↩ cola no app da frente (ou copia, sem a colagem automática). Os nomes vêm do próprio macOS (Unicode).
enum EmojiSearch {
    /// Todos os emoji com o nome Unicode em minúsculas ("rocket", "red heart"), montado uma vez
    nonisolated(unsafe) private static var index: [(char: String, name: String)] = {
        var out: [(String, String)] = []
        let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF,
                                             0x1FA70...0x1FAFF, 0x2600...0x26FF, 0x2700...0x27BF]
        for range in ranges {
            for v in range {
                guard let scalar = Unicode.Scalar(v), scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && v >= 0x2600 && v < 0x2800 && scalar.properties.generalCategory == .otherSymbol) else { continue }
                let s = String(scalar)
                guard let raw = s.applyingTransform(.toUnicodeName, reverse: false) else { continue }
                // "\N{ROCKET}" → "rocket"
                let name = raw.replacingOccurrences(of: "\\N{", with: "").replacingOccurrences(of: "}", with: "").lowercased()
                out.append((s, name))
            }
        }
        // ❤️ e alguns com seletor de variação, que o laço acima não pega
        out.append(("❤️", "red heart"))
        return out
    }()

    /// Palavras em português, alemão, espanhol e chinês para os nomes em inglês
    private static let words: [String: String] = [
        "coracao": "heart", "coração": "heart", "amor": "heart", "herz": "heart", "corazon": "heart", "corazón": "heart", "心": "heart",
        "foguete": "rocket", "rakete": "rocket", "cohete": "rocket", "火箭": "rocket",
        "risada": "joy", "rindo": "laughing", "rir": "laughing", "lachen": "laughing", "risa": "laughing", "笑": "laughing",
        "sorriso": "smiling", "feliz": "smiling", "lächeln": "smiling", "sonrisa": "smiling", "微笑": "smiling",
        "triste": "crying", "chorando": "crying", "weinen": "crying", "llorando": "crying", "哭": "crying",
        "fogo": "fire", "feuer": "fire", "fuego": "fire", "火": "fire",
        "joinha": "thumbs up", "positivo": "thumbs up", "daumen": "thumbs up", "pulgar": "thumbs up", "赞": "thumbs up",
        "palmas": "clapping", "aplausos": "clapping", "klatschen": "clapping", "鼓掌": "clapping",
        "festa": "party", "comemorar": "party", "party": "party", "fiesta": "party", "派对": "party",
        "estrela": "star", "stern": "star", "estrella": "star", "星": "star",
        "check": "check mark", "certo": "check mark", "ok": "ok", "feito": "check mark", "erledigt": "check mark", "hecho": "check mark",
        "errado": "cross mark", "xis": "cross mark", "falsch": "cross mark", "mal": "cross mark",
        "cafe": "hot beverage", "café": "hot beverage", "kaffee": "hot beverage", "咖啡": "hot beverage",
        "cerveja": "beer", "bier": "beer", "cerveza": "beer", "啤酒": "beer",
        "olhos": "eyes", "augen": "eyes", "ojos": "eyes", "眼睛": "eyes",
        "pensando": "thinking", "denken": "thinking", "pensar": "thinking", "思考": "thinking",
        "oracao": "folded hands", "oração": "folded hands", "obrigado": "folded hands", "beten": "folded hands", "gracias": "folded hands", "谢谢": "folded hands",
        "musculo": "biceps", "músculo": "biceps", "forca": "biceps", "força": "biceps", "muskel": "biceps", "fuerza": "biceps",
        "cachorro": "dog", "hund": "dog", "perro": "dog", "狗": "dog", "gato": "cat", "katze": "cat", "猫": "cat",
        "sol": "sun", "sonne": "sun", "太阳": "sun", "chuva": "rain", "regen": "rain", "lluvia": "rain", "雨": "rain",
        "dinheiro": "money", "geld": "money", "dinero": "money", "钱": "money",
        "presente": "gift", "geschenk": "gift", "regalo": "gift", "礼物": "gift",
        "alerta": "warning", "aviso": "warning", "warnung": "warning", "警告": "warning",
        "ideia": "light bulb", "idee": "light bulb", "idea": "light bulb", "想法": "light bulb",
        "relogio": "clock", "relógio": "clock", "uhr": "clock", "reloj": "clock", "时钟": "clock",
        "computador": "computer", "computer": "computer", "电脑": "computer", "telefone": "telephone", "celular": "mobile phone",
        "pizza": "pizza", "bolo": "cake", "kuchen": "cake", "pastel": "cake", "蛋糕": "cake",
        "brasil": "flag", "100": "hundred points", "caveira": "skull", "fantasma": "ghost", "cocô": "pile of poo", "coco": "pile of poo",
    ]

    private static let preferred = ["heart": "❤️", "thumbs up": "👍", "joy": "😂", "smiling": "😊", "crying": "😢", "fire": "🔥",
                                    "party": "🎉", "star": "⭐", "check mark": "✅", "hot beverage": "☕", "thinking": "🤔", "folded hands": "🙏"]

    static let prefixes = ["emoji ", "emojis ", ":"]

    /// Até 8 emoji para o texto depois de "emoji " ou ":"
    static func emoji(for raw: String) -> [(char: String, name: String)] {
        let q = PaletteSearch.fold(raw.trimmingCharacters(in: .whitespaces))
        guard q.count >= 2 else { return [] }
        let english = words[q] ?? words.first { q.count >= 4 && $0.key.hasPrefix(q) }?.value ?? q
        let hits = index.filter { $0.name.split(separator: " ").contains { $0.hasPrefix(english) } || $0.name.contains(english) }
        // O mais óbvio primeiro (❤️ para "coração"), depois os que têm a palavra inteira, depois os nomes mais curtos
        func rank(_ e: (char: String, name: String)) -> Int {
            if preferred[english] == e.char { return 0 }
            return e.name.split(separator: " ").contains { $0 == english } ? 1 : 2
        }
        return Array(hits.sorted { (rank($0), $0.name.count) < (rank($1), $1.name.count) }.prefix(8))
    }

    /// Símbolos que não têm tecla, com palavras nos cinco idiomas
    static let symbols: [(char: String, keywords: String)] = [
        ("→", "seta direita arrow right pfeil rechts flecha derecha 箭头 右"), ("←", "seta esquerda arrow left pfeil links flecha izquierda 箭头 左"),
        ("↑", "seta cima arrow up pfeil oben flecha arriba 箭头 上"), ("↓", "seta baixo arrow down pfeil unten flecha abajo 箭头 下"),
        ("⇒", "seta dupla implica implies doppelpfeil flecha doble"), ("↔", "seta dupla ambos arrow both"),
        ("✓", "check certo visto tick haken marca 勾"), ("✗", "xis errado cross falsch cruz 叉"),
        ("•", "ponto bolinha bullet punkt viñeta 圆点"), ("…", "reticencias reticências ellipsis auslassung puntos suspensivos 省略号"),
        ("—", "travessao travessão em dash gedankenstrich raya 破折号"), ("–", "meia risca en dash halbgeviertstrich guion"),
        ("°", "grau graus degree grad grado 度"), ("±", "mais ou menos plus minus más menos 正负"),
        ("×", "vezes multiplicacao multiplicação times mal por 乘"), ("÷", "divisao divisão divide geteilt dividido 除"),
        ("≈", "aproximadamente approximately ungefähr aproximado 约等于"), ("≠", "diferente not equal ungleich distinto 不等于"),
        ("≤", "menor ou igual less equal kleiner gleich menor igual 小于等于"), ("≥", "maior ou igual greater equal größer gleich mayor igual 大于等于"),
        ("∞", "infinito infinity unendlich 无穷"), ("π", "pi"), ("√", "raiz quadrada square root wurzel raíz 根号"),
        ("½", "meio metade half halb medio 二分之一"), ("¼", "um quarto quarter viertel cuarto"), ("¾", "tres quartos três quartos three quarters"),
        ("²", "ao quadrado squared hoch zwei cuadrado 平方"), ("³", "ao cubo cubed hoch drei cubo 立方"),
        ("€", "euro"), ("£", "libra pound pfund"), ("¥", "iene yen yuan 元"), ("₿", "bitcoin"),
        ("©", "copyright direitos autorais derechos"), ("®", "registrado registered eingetragen registrado"), ("™", "marca registrada trademark marke"),
        ("§", "paragrafo parágrafo section paragraph párrafo"), ("¶", "pilcrow parágrafo"),
        ("⌘", "command comando cmd befehl"), ("⌥", "option opcao opção alt"), ("⌃", "control controle ctrl steuerung"),
        ("⇧", "shift maiusculas maiúsculas umschalt mayúsculas"), ("⏎", "return enter"), ("⌫", "delete apagar backspace löschen borrar"),
        ("", "apple maçã logo"),
    ]

    @MainActor static func paletteItems(raw: String, query q: String) -> [PaletteItem] {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let prefix = prefixes.first(where: { text.lowercased().hasPrefix($0) }) {
            return emoji(for: String(text.dropFirst(prefix.count))).map { e in
                item(id: "emoji.\(e.char)", char: e.char, title: e.name.capitalized, kind: .calc)
            }
        }
        guard q.count >= 3 else { return [] }
        return symbols.compactMap { s in
            guard PaletteSearch.score(q, title: "", keywords: s.keywords) != nil else { return nil }
            let parts = s.keywords.split(separator: " ")
            let name = (parts.first == "seta" ? parts.prefix(2) : parts.prefix(1)).joined(separator: " ")
            return item(id: "symbol.\(s.char)", char: s.char, title: name.capitalized, kind: .action, keywords: s.keywords)
        }
    }

    @MainActor private static func item(id: String, char: String, title: String, kind: PaletteItem.Kind, keywords: String = "") -> PaletteItem {
        PaletteItem(id: id, kind: kind, title: title, subtitle: L("↩ cola no app da frente"), keywords: keywords,
                    icon: .glyph(char), remember: false) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(char, forType: .string)
            guard UserDefaults.standard.bool(forKey: "autoPaste"), AXIsProcessTrusted() else {
                HUD.show(icon: "doc.on.doc.fill", color: .gray, text: L("Copiado: %@", char))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { ClipboardManager.postCommandV() }
        }
    }
}
