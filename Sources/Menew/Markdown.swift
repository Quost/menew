import SwiftUI

/// Markdown em blocos: títulos, listas, checklists clicáveis, citações, código e linhas.
/// O inline (negrito, itálico, `código`, links) fica com o AttributedString do sistema.
struct MarkdownView: View {
    let text: String
    /// Recebe o índice da linha do checklist clicado
    var onToggleTask: ((Int) -> Void)?
    /// Recebe a tag clicada
    var onTag: ((String) -> Void)?

    private enum Block {
        case heading(Int, String)
        case task(Bool, String, line: Int)
        case bullet(String, indent: Int)
        case numbered(String, String)
        case quote(String)
        case code(String)
        case rule
        case paragraph(String)
        case space
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "menew-tag" {
                onTag?(url.host() ?? "")
                return .handled
            }
            return .systemAction
        })
    }

    // MARK: Blocos

    private var blocks: [Block] {
        var out: [Block] = []
        var code: [String]?
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }

            if line.isEmpty { out.append(.space); continue }
            if line == "---" || line == "***" { out.append(.rule); continue }
            if let m = line.firstMatch(of: #/^(#{1,3})\s+(.+)$/#) {
                out.append(.heading(m.1.count, String(m.2))); continue
            }
            if let m = line.firstMatch(of: #/^[-*+]\s+\[([ xX])\]\s*(.*)$/#) {
                out.append(.task(m.1 != " ", String(m.2), line: i)); continue
            }
            if let m = line.firstMatch(of: #/^[-*+]\s+(.+)$/#) {
                let indent = raw.prefix { $0 == " " || $0 == "\t" }.count / 2
                out.append(.bullet(String(m.1), indent: indent)); continue
            }
            if let m = line.firstMatch(of: #/^(\d+)[.)]\s+(.+)$/#) {
                out.append(.numbered(String(m.1), String(m.2))); continue
            }
            if let m = line.firstMatch(of: #/^>\s?(.*)$/#) {
                out.append(.quote(String(m.1))); continue
            }
            out.append(.paragraph(line))
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        // Sem espaços duplicados nem no começo/fim
        return out.enumerated().filter { i, b in
            guard case .space = b else { return true }
            if i == 0 || i == out.count - 1 { return false }
            if case .space = out[i - 1] { return false }
            return true
        }.map(\.element)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let s):
            inline(s, size: level == 1 ? 18 : level == 2 ? 15.5 : 13.5, weight: .bold)
                .padding(.top, level == 1 ? 2 : 4)
        case .task(let done, let s, let line):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Button { onToggleTask?(line) } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(done ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                inline(s).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
            }
        case .bullet(let s, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(indent > 0 ? "◦" : "•").foregroundStyle(.secondary)
                inline(s)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(n).").foregroundStyle(.secondary).monospacedDigit()
                inline(s)
            }
        case .quote(let s):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.violet.opacity(0.6)).frame(width: 3)
                inline(s).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let s):
            Text(s)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        case .rule:
            Divider().padding(.vertical, 4)
        case .paragraph(let s):
            inline(s)
        case .space:
            Spacer().frame(height: 4)
        }
    }

    // MARK: Inline

    /// Negrito, itálico, código e links do Markdown; #tags viram links internos
    private func inline(_ s: String, size: CGFloat = 13, weight: Font.Weight = .regular) -> Text {
        let withTags = s.replacing(#/(^|\s)#([\p{L}\p{N}_-]+)/#) { m in
            "\(m.1)[#\(m.2)](menew-tag://\(m.2.lowercased()))"
        }
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var attr = (try? AttributedString(markdown: withTags, options: opts)) ?? AttributedString(s)
        for run in attr.runs where run.link?.scheme == "menew-tag" {
            attr[run.range].foregroundColor = Theme.violet
        }
        return Text(attr).font(.system(size: size, weight: weight))
    }
}
