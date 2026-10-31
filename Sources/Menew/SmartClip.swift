import AppKit
import SwiftUI

/// Clipboard esperto: reconhece o que você copiou (link de reunião, telefone, endereço, e-mail, código de rastreio, cor)
/// e oferece a ação certa na paleta e no histórico. Tudo é reconhecido no Mac; as ações abrem o app ou o navegador.
struct SmartAction {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let keywords: String
    let run: () -> Void
}

@MainActor
enum SmartClip {
    private static var cache: (text: String, actions: [SmartAction])?

    static func actions(for raw: String) -> [SmartAction] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 400 else { return [] }
        if let cache, cache.text == text { return cache.actions }
        let found = detect(text)
        cache = (text, found)
        return found
    }

    private static func detect(_ text: String) -> [SmartAction] {
        var out: [SmartAction] = []
        let short = text.count > 60 ? String(text.prefix(57)) + "…" : text

        if let link = MeetingStore.meetingLink(in: text) {
            out.append(SmartAction(id: "meeting", title: L("Entrar na reunião"), subtitle: link.host() ?? short, icon: "video.fill",
                                   color: .green, keywords: "entrar reunião reuniao join meeting zoom meet teams beitreten unirse 加入") {
                NSWorkspace.shared.open(link)
            })
        }

        if let color = parseColor(text) {
            for (label, value) in [("HEX", color.hex), ("RGB", color.rgb), ("HSL", color.hsl)] where value.lowercased() != text.lowercased() {
                out.append(SmartAction(id: "color.\(label)", title: L("Copiar como %@", value), subtitle: L("Cor copiada: %@", short),
                                       icon: "paintpalette.fill", color: .purple, keywords: "cor color hex rgb hsl farbe 颜色 \(label.lowercased())") {
                    copy(value)
                })
            }
        }

        if let code = trackingCode(text) {
            let url = code.hasSuffix("BR")
                ? URL(string: "https://rastreamento.correios.com.br/app/index.php?objetos=\(code)")
                : URL(string: "https://parcelsapp.com/en/tracking/\(code)")
            if let url {
                out.append(SmartAction(id: "tracking", title: L("Rastrear encomenda %@", code), subtitle: url.host() ?? "",
                                       icon: "shippingbox.fill", color: .brown,
                                       keywords: "rastrear rastreio encomenda pacote correios track tracking package sendung verfolgen rastrear 快递 追踪") {
                    NSWorkspace.shared.open(url)
                })
            }
        }

        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .address, .link]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return out }
        let ns = text as NSString
        // Só quando o texto é praticamente só aquilo (um telefone, um endereço), não uma frase com um número no meio
        for m in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.range.length * 10 >= ns.length * 7 {
            switch m.resultType {
            case .phoneNumber:
                guard let phone = m.phoneNumber else { continue }
                let digits = phone.filter { $0.isNumber || $0 == "+" }
                if let tel = URL(string: "tel:\(digits)") {
                    out.append(SmartAction(id: "phone", title: L("Ligar para %@", phone), subtitle: L("Pelo FaceTime ou iPhone"),
                                           icon: "phone.fill", color: .green, keywords: "ligar telefone call phone anrufen llamar 电话 \(digits)") {
                        NSWorkspace.shared.open(tel)
                    })
                }
                // O WhatsApp precisa do código do país: sem "+", usa o do Mac (Brasil, Portugal, EUA…)
                var wa = digits.filter(\.isNumber)
                if !digits.hasPrefix("+"), let cc = countryCodes[Locale.current.region?.identifier ?? ""] { wa = cc + wa }
                if digits.hasPrefix("+") || countryCodes[Locale.current.region?.identifier ?? ""] != nil,
                   wa.count >= 10, let url = URL(string: "https://wa.me/\(wa)") {
                    out.append(SmartAction(id: "whatsapp", title: L("Abrir conversa no WhatsApp"), subtitle: phone,
                                           icon: "message.fill", color: .green, keywords: "whatsapp zap mensagem message chat") {
                        NSWorkspace.shared.open(url)
                    })
                }
            case .address:
                let address = ns.substring(with: m.range)
                if let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: "https://maps.apple.com/?q=\(q)") {
                    out.append(SmartAction(id: "address", title: L("Abrir no Mapas"), subtitle: short, icon: "map.fill", color: .blue,
                                           keywords: "mapa mapas maps endereço endereco address karte mapa 地图") {
                        NSWorkspace.shared.open(url)
                    })
                }
            case .link:
                guard let url = m.url, !out.contains(where: { $0.id == "meeting" }) else { continue }
                if url.scheme == "mailto" {
                    out.append(SmartAction(id: "mail", title: L("Escrever para %@", url.absoluteString.replacingOccurrences(of: "mailto:", with: "")),
                                           subtitle: L("No seu app de e-mail"), icon: "envelope.fill", color: .blue,
                                           keywords: "email e-mail escrever mail write schreiben correo 邮件") { NSWorkspace.shared.open(url) })
                } else {
                    out.append(SmartAction(id: "link", title: L("Abrir %@", url.host() ?? short), subtitle: url.absoluteString,
                                           icon: "safari.fill", color: .blue, keywords: "abrir link open url öffnen abrir 打开") {
                        NSWorkspace.shared.open(url)
                    })
                }
            default: break
            }
        }
        return out
    }

    private static let countryCodes = ["BR": "55", "PT": "351", "US": "1", "CA": "1", "ES": "34", "DE": "49", "MX": "52",
                                       "AR": "54", "GB": "44", "FR": "33", "IT": "39", "CN": "86", "IN": "91"]

    private static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        HUD.show(icon: "doc.on.doc.fill", color: .gray, text: L("Copiado: %@", value))
    }

    /// Correios e padrão internacional (AA123456789BR) e UPS (1Z…)
    private static func trackingCode(_ text: String) -> String? {
        let t = text.uppercased().replacingOccurrences(of: " ", with: "")
        let patterns = [#"^[A-Z]{2}\d{9}[A-Z]{2}$"#, #"^1Z[0-9A-Z]{16}$"#]
        return patterns.contains { t.range(of: $0, options: .regularExpression) != nil } ? t : nil
    }

    struct ParsedColor {
        let r: Int, g: Int, b: Int
        var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
        var rgb: String { "rgb(\(r), \(g), \(b))" }
        var hsl: String {
            let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
            let mx = max(rf, gf, bf), mn = min(rf, gf, bf), l = (mx + mn) / 2
            var h = 0.0, s = 0.0
            if mx != mn {
                let d = mx - mn
                s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
                if mx == rf { h = (gf - bf) / d + (gf < bf ? 6 : 0) } else if mx == gf { h = (bf - rf) / d + 2 } else { h = (rf - gf) / d + 4 }
                h /= 6
            }
            return "hsl(\(Int((h * 360).rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        }
    }

    /// "#3B82F6", "#38f", "rgb(59, 130, 246)"
    static func parseColor(_ text: String) -> ParsedColor? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.range(of: #"^#([0-9a-f]{3}|[0-9a-f]{6})$"#, options: .regularExpression) != nil {
            var hex = String(t.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let v = Int(hex, radix: 16) else { return nil }
            return ParsedColor(r: v >> 16 & 0xFF, g: v >> 8 & 0xFF, b: v & 0xFF)
        }
        if t.hasPrefix("rgb"), let open = t.firstIndex(of: "("), let close = t.lastIndex(of: ")") {
            let nums = t[t.index(after: open)..<close].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count >= 3, nums.prefix(3).allSatisfy({ (0...255).contains($0) }) { return ParsedColor(r: nums[0], g: nums[1], b: nums[2]) }
        }
        return nil
    }

    /// Para a paleta
    static func paletteItems(text: String) -> [PaletteItem] {
        actions(for: text).map { a in
            PaletteItem(id: "smart.\(a.id)", kind: .action, title: a.title, subtitle: a.subtitle, keywords: a.keywords,
                        icon: .symbol(a.icon, a.color), remember: false, run: a.run)
        }
    }
}
