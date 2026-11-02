import SwiftUI

/// Grafo do conhecimento: os assuntos que a IA achou (ferramentas, pessoas, projetos, etiquetas) ligados aos itens
/// guardados e às notas com #tags. Um assunto que aparece em vários itens fica maior e no meio.
struct KnowledgeGraph: Sendable {
    struct Node: Identifiable, Sendable {
        enum Kind: Sendable { case topic, memory(UUID), note(UUID) }
        let id: String
        let label: String
        let kind: Kind
        var weight: Int
    }

    var nodes: [Node] = []
    var edges: [(Int, Int)] = []

    var isTopic: [Bool] { nodes.map { if case .topic = $0.kind { true } else { false } } }

    /// No máximo 40 assuntos (os mais ligados) e os itens ligados a eles
    static func build(memory: [MemoryItem], notes: [Note], maxTopics: Int = 40) -> KnowledgeGraph {
        var topicLabel: [String: String] = [:]
        var links: [(item: Node, topics: [String])] = []
        func key(_ s: String) -> String { PaletteSearch.fold(s.trimmingCharacters(in: .whitespaces)) }
        for m in memory {
            let ts = Array(Set((m.entities + m.tags).map(key).filter { $0.count >= 2 }))
            for t in m.entities + m.tags where topicLabel[key(t)] == nil { topicLabel[key(t)] = t }
            if !ts.isEmpty { links.append((Node(id: "m:\(m.id)", label: m.title, kind: .memory(m.id), weight: 1), ts)) }
        }
        for n in notes where !n.secure && !n.isPasswords {
            let ts = n.tags.map(key)
            for t in n.tags where topicLabel[key(t)] == nil { topicLabel[key(t)] = "#" + t }
            if !ts.isEmpty { links.append((Node(id: "n:\(n.id)", label: n.title, kind: .note(n.id), weight: 1), ts)) }
        }
        var count: [String: Int] = [:]
        for l in links { for t in l.topics { count[t, default: 0] += 1 } }
        let top = Set(count.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.prefix(maxTopics).map(\.key))
        var g = KnowledgeGraph()
        var topicIndex: [String: Int] = [:]
        for t in top.sorted() {
            topicIndex[t] = g.nodes.count
            g.nodes.append(Node(id: "t:\(t)", label: topicLabel[t] ?? t, kind: .topic, weight: count[t] ?? 1))
        }
        for l in links {
            let ts = l.topics.filter { top.contains($0) }
            guard !ts.isEmpty else { continue }
            let i = g.nodes.count
            g.nodes.append(l.item)
            for t in ts { if let j = topicIndex[t] { g.edges.append((i, j)) } }
        }
        return g
    }

    /// Largura aproximada de cada nó na tela (assuntos são cápsulas com texto; itens, pontos)
    func boxSize(_ i: Int) -> CGSize {
        if case .topic = nodes[i].kind {
            let font = min(15, 11 + Double(nodes[i].weight))
            return CGSize(width: Double(nodes[i].label.count) * font * 0.58 + 22, height: font + 12)
        }
        return CGSize(width: 14, height: 14)
    }

    /// Posições por forças (Fruchterman-Reingold), sempre iguais para os mesmos dados; no fim, nomes que se
    /// encostam são afastados
    func layout(in size: CGSize, iterations: Int = 300) -> [CGPoint] {
        let n = nodes.count
        guard n > 0, size.width > 40, size.height > 40 else { return [] }
        var pos: [CGPoint] = nodes.map { node in
            var h: UInt64 = 1469598103934665603
            for b in node.id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
            return CGPoint(x: size.width * (0.25 + Double(h % 1000) / 2000), y: size.height * (0.25 + Double((h / 1000) % 1000) / 2000))
        }
        let k = sqrt(size.width * size.height / Double(max(n, 1))) * 0.42
        var temp = size.width / 10
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for _ in 0..<iterations {
            var disp = [CGVector](repeating: .zero, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y
                    var d = sqrt(dx * dx + dy * dy)
                    if d < 0.01 { dx = 0.1; dy = 0.1; d = 0.14 }
                    let f = k * k / d
                    disp[i].dx += dx / d * f; disp[i].dy += dy / d * f
                    disp[j].dx -= dx / d * f; disp[j].dy -= dy / d * f
                }
            }
            for (a, b) in edges {
                let dx = pos[a].x - pos[b].x, dy = pos[a].y - pos[b].y
                let d = max(0.01, sqrt(dx * dx + dy * dy))
                let f = d * d / k
                disp[a].dx -= dx / d * f; disp[a].dy -= dy / d * f
                disp[b].dx += dx / d * f; disp[b].dy += dy / d * f
            }
            for i in 0..<n {
                // Gravidade: tudo puxa para o meio; assuntos mais ligados, mais forte
                let g = 0.16 * (1 + Double(nodes[i].weight) * 0.3)
                disp[i].dx += (center.x - pos[i].x) * g * k / 10
                disp[i].dy += (center.y - pos[i].y) * g * k / 10
                let d = max(0.01, sqrt(disp[i].dx * disp[i].dx + disp[i].dy * disp[i].dy))
                pos[i].x += disp[i].dx / d * min(d, temp)
                pos[i].y += disp[i].dy / d * min(d, temp)
            }
            temp = max(0.5, temp * 0.97)
        }
        // Afasta caixas que se sobrepõem e mantém tudo dentro da área
        for _ in 0..<120 {
            var moved = false
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let a = boxSize(i), b = boxSize(j)
                    let ox = (a.width + b.width) / 2 + 6 - abs(pos[i].x - pos[j].x)
                    let oy = (a.height + b.height) / 2 + 4 - abs(pos[i].y - pos[j].y)
                    guard ox > 0, oy > 0 else { continue }
                    moved = true
                    // Perto de cima ou de baixo não dá para empurrar na vertical: vai para os lados
                    let nearEdge = min(pos[i].y, pos[j].y) < a.height + 8 || max(pos[i].y, pos[j].y) > size.height - b.height - 8
                    if oy < ox && !nearEdge {
                        let s = (pos[i].y < pos[j].y ? -1.0 : 1.0) * oy / 2
                        pos[i].y += s; pos[j].y -= s
                    } else {
                        let s = (pos[i].x < pos[j].x ? -1.0 : 1.0) * ox / 2
                        pos[i].x += s; pos[j].x -= s
                    }
                }
            }
            for i in 0..<n {
                let b = boxSize(i)
                pos[i].x = min(size.width - b.width / 2 - 4, max(b.width / 2 + 4, pos[i].x))
                pos[i].y = min(size.height - b.height / 2 - 4, max(b.height / 2 + 4, pos[i].y))
            }
            if !moved { break }
        }
        return pos
    }
}

/// O grafo desenhado: linhas finas, assuntos em cápsulas coloridas (maiores quanto mais ligados), itens em pontos
struct KnowledgeGraphView: View {
    let graph: KnowledgeGraph
    var onTopic: (String) -> Void
    var onMemory: (UUID) -> Void
    var onNote: (UUID) -> Void
    @State private var hover: String?
    @State private var pos: [CGPoint] = []
    @State private var laidOut: String = ""

    init(graph: KnowledgeGraph, positions: [CGPoint] = [], onTopic: @escaping (String) -> Void, onMemory: @escaping (UUID) -> Void, onNote: @escaping (UUID) -> Void) {
        self.graph = graph
        self.onTopic = onTopic
        self.onMemory = onMemory
        self.onNote = onNote
        _pos = State(initialValue: positions)
    }

    private static let palette: [Color] = [.pink, .purple, .indigo, .blue, .teal, .green, .orange]

    var body: some View {
        GeometryReader { g in
            // As posições só são recalculadas quando muda o tamanho ou os dados (não a cada movimento do mouse)
            let sig = "\(Int(g.size.width))x\(Int(g.size.height)):\(graph.nodes.count):\(graph.edges.count)"
            Group {
            if pos.count == graph.nodes.count, !pos.isEmpty {
                ZStack {
                    Canvas { ctx, _ in
                        for (a, b) in graph.edges {
                            var p = Path()
                            p.move(to: pos[a]); p.addLine(to: pos[b])
                            let lit = hover == graph.nodes[a].id || hover == graph.nodes[b].id
                            ctx.stroke(p, with: .color(lit ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12)), lineWidth: lit ? 1.6 : 1)
                        }
                    }
                    ForEach(Array(graph.nodes.enumerated()), id: \.element.id) { i, node in
                        nodeView(node, i).position(pos[i])
                    }
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            }
            .task(id: sig) {
                guard laidOut != sig else { return }
                let gr = graph, size = g.size
                pos = await Task.detached { gr.layout(in: size) }.value
                laidOut = sig
            }
        }
    }

    @ViewBuilder private func nodeView(_ node: KnowledgeGraph.Node, _ i: Int) -> some View {
        switch node.kind {
        case .topic:
            let c = Self.palette[node.label.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.palette.count]
            Button { onTopic(node.label.hasPrefix("#") ? String(node.label.dropFirst()) : node.label) } label: {
                Text(node.label)
                    .font(.system(size: min(15, 11 + CGFloat(node.weight)), weight: .semibold)).lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(c.opacity(hover == node.id ? 0.32 : 0.18)))
                    .foregroundStyle(c)
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 ? node.id : nil }
            .help(L("%d itens · clique para filtrar", node.weight))
        case .memory(let id):
            dot(node, Color.secondary) { onMemory(id) }
        case .note(let id):
            dot(node, Color.yellow) { onNote(id) }
        }
    }

    private func dot(_ node: KnowledgeGraph.Node, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Circle().fill(color.opacity(0.7)).frame(width: 9, height: 9)
                if hover == node.id {
                    Text(node.label).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.regularMaterial))
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 ? node.id : nil }
        .help(node.label)
    }
}
