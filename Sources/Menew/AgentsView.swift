import AppKit
import Charts
import SwiftUI

/// Janela Menew › Agentes de IA: quem está rodando, os limites, o uso e a configuração (hooks e MCP)
struct AgentsView: View {
    @ObservedObject var usage = AgentUsageStore.shared
    @ObservedObject var hub = AgentHub.shared
    @ObservedObject var mcpStatus = MCPStatus.shared
    @State private var range = AgentsView.savedRange
    /// Barras empilhadas por ferramenta (true) ou o total somado
    @AppStorage("agents.usageByTool") private var byTool = true
    @State private var confirm: (AgentKind, Bool)?
    @State private var error: String?
    /// Muda a cada instalação, para os status (lidos dos arquivos) serem lidos de novo
    @State private var tick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                running
                limits
                usageCard
                if !usage.localModels.isEmpty { localModels }
                setup
                mcp
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .onAppear { usage.isVisible = true; hub.isVisible = true; mcpStatus.refresh() }
        .onDisappear { usage.isVisible = false; hub.isVisible = false }
        .alert(item: Binding(get: { confirm.map { ConfirmBox(agent: $0.0, install: $0.1) } }, set: { _ in confirm = nil })) { c in
            Alert(title: Text(c.install ? L("Ligar os avisos do %@?", c.agent.name) : L("Desligar os avisos do %@?", c.agent.name)),
                  message: Text(c.install
                                ? (AgentPlugins.supports(c.agent)
                                    ? L("O Menew põe um plugin dele em %@. Ele só escreve cada evento num arquivo ao lado; nada sai do computador. Reabra a ferramenta para carregar.", AgentHooks.configURL(c.agent).deletingLastPathComponent().path)
                                    : L("O Menew acrescenta um comando dele nos hooks de %@ (uma cópia do arquivo fica em .menew-backup). O resto do arquivo não muda.", AgentHooks.configURL(c.agent).path))
                                    + (c.agent == .codex ? "\n\n" + L("O Codex (também o de dentro do app ChatGPT) só roda hooks aprovados: o Menew grava a aprovação dos comandos dele em %@.", CodexHookTrust.configURL.path) : "")
                                : L("O Menew tira só as entradas dele de %@.", AgentHooks.configURL(c.agent).path)),
                  primaryButton: .default(Text(c.install ? L("Ligar") : L("Desligar"))) {
                      do { try AgentHooks.apply(c.agent, install: c.install) } catch { self.error = L("Não consegui alterar %@.", AgentHooks.configURL(c.agent).lastPathComponent) }
                      tick += 1
                  },
                  secondaryButton: .cancel(Text(L("Cancelar"))))
        }
    }

    private struct ConfirmBox: Identifiable { let agent: AgentKind; let install: Bool; var id: String { agent.rawValue } }

    // MARK: Rodando agora

    private var running: some View {
        section(L("Agora"), trailing: nil) {
            let list = hub.visible
            if list.isEmpty {
                Text(AgentKind.allCases.contains { AgentHooks.status($0) == .installed }
                     ? L("Nenhum agente rodando. Quando um terminar ou precisar de você, o Menew avisa no notch.")
                     : L("Nenhum agente rodando. Ligue os avisos abaixo para ver quem está trabalhando, quem terminou e quem espera você."))
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 6) {
                        ForEach(list) { s in sessionRow(s, now: ctx.date) }
                    }
                }
            }
        }
    }

    private func sessionRow(_ s: AgentSession, now: Date) -> some View {
        HStack(spacing: 10) {
            agentBadge(s.agent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.project).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(s.agent.name).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                if let m = s.message, s.state == .waiting {
                    Text(m).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                } else if let c = s.cwd {
                    Text(c.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if s.state == .working, let t = s.turnStart {
                Text(NotchView.clock(now.timeIntervalSince(t))).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
            }
            pill(s.stateTitle, s.stateColor)
            Button(L("Abrir")) { hub.focus(s) }.controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: Limites

    private var limits: some View {
        section(L("Limites do plano"), trailing: nil) {
            let agents = AgentKind.allCases.filter { usage.limits[$0] != nil }
            if agents.isEmpty && !ClaudePlanLimits.isOn {
                Text(L("O Codex grava os limites enquanto você usa; eles aparecem aqui. Para os do Claude, ligue “Limites do Claude” em Configurar."))
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 24, alignment: .top)], alignment: .leading, spacing: 12) {
            ForEach(agents) { a in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        agentBadge(a)
                        Text(a.name).font(.system(size: 13, weight: .semibold))
                        if let p = usage.plans[a] { pill(p, a.color) }
                        Spacer()
                        if a == .codex, let asOf = usage.limits[a]?.first?.asOf, Date().timeIntervalSince(asOf) > 600 {
                            Text(L("lido %@", asOf.formatted(.relative(presentation: .named).locale(L10n.locale)))).font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                    ForEach(usage.current(a)) { w in windowBar(w, agent: a, color: a.color) }
                }
                .padding(.vertical, 4)
            }
            }
            if ClaudePlanLimits.isOn, let e = usage.claudeLimitError {
                Label(claudeError(e), systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.orange)
            }
        }
    }

    private func claudeError(_ e: ClaudePlanLimits.Failure) -> String {
        switch e {
        case .noLogin: L("Não achei o login do Claude Code neste Mac.")
        case .expired: L("O login do Claude Code venceu. Abra o Claude Code e o Menew lê de novo.")
        case .network: L("Sem resposta da Anthropic agora. Tento de novo em alguns minutos.")
        case .format: L("A Anthropic mudou o formato dos limites. Os dados do Mac continuam aqui.")
        }
    }

    private func windowBar(_ w: RateWindow, agent: AgentKind, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(w.label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(w.usedPercent.rounded()))%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(w.usedPercent >= 90 ? .red : w.usedPercent >= 75 ? .orange : .primary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill((w.usedPercent >= 90 ? Color.red : w.usedPercent >= 75 ? .orange : color).gradient)
                        .frame(width: max(4, g.size.width * min(1, w.usedPercent / 100)))
                }
            }
            .frame(height: 7)
            HStack(spacing: 10) {
                if let r = w.resetsAt {
                    Text(L("zera %@", r.formatted(.relative(presentation: .named).locale(L10n.locale))))
                }
                if let p = usage.projection(agent, w) {
                    Label(p.text + " · " + p.paceText, systemImage: p.runsOut != nil ? "exclamationmark.triangle.fill" : "speedometer")
                        .foregroundStyle(p.runsOut != nil ? Color.orange : .secondary)
                        .help(p.recent ? L("Pelo ritmo da última hora") : L("Pelo ritmo médio desde o começo da janela"))
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: Uso

    private static let rangeKey = "agents.usageRange"

    /// O período escolhido da última vez (nas capturas de tela, 12 meses)
    static var savedRange: UsageRange {
        if AgentUsageStore.shared.isDemo { return .year }
        return UserDefaults.standard.string(forKey: rangeKey).flatMap(UsageRange.init) ?? .week
    }

    private var usageCard: some View {
        let h = usage.history
        let w = h.window(range)
        let t = h.totals(since: w.start)
        return section(L("Uso"), trailing: AnyView(
            Picker("", selection: Binding(get: { range }, set: { range = $0; if !usage.isDemo { UserDefaults.standard.set($0.rawValue, forKey: Self.rangeKey) } })) {
                ForEach(UsageRange.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
        )) {
            if h.rows.isEmpty && usage.records.isEmpty {
                Text(usage.installed.isEmpty
                     ? L("Nenhum agente de IA neste Mac.")
                     : (usage.scanning ? L("Lendo os registros…") : L("Nenhum uso registrado.")))
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .bottom, spacing: 24) {
                    stat(L("Tokens"), Self.tokens(t.tokens))
                    stat(L("Custo estimado"), Self.money(t.cost), help: L("O Claude pelos preços da API da Anthropic (no plano Pro ou Max você não paga isso); as outras pelo custo que elas mesmas gravam, e o Kiro pelos créditos."))
                    stat(L("Economia do cache"), Self.money(t.savings), help: L("Quanto as leituras do cache custariam como entrada normal"))
                    stat(L("Respostas"), t.replies.formatted(.number.locale(L10n.locale)))
                    Spacer(minLength: 0)
                    if range != .today {
                        Picker("", selection: $byTool) {
                            Text(L("Por ferramenta")).tag(true)
                            Text(L("Somado")).tag(false)
                        }.pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                    }
                }
                if range != .today { chart(h, w) }
                HStack(alignment: .top, spacing: 24) {
                    ranking(L("Modelos"), h.top(since: w.start, by: { AgentPricing.displayName($0.model) }))
                    ranking(L("Projetos"), h.top(since: w.start, by: \.project))
                    ranking(L("Apps"), h.top(since: w.start, by: { $0.client.title($0.agent) }))
                }
                HStack(spacing: 14) {
                    ForEach(AgentKind.allCases.filter { usage.burnRate($0) > 0 }) { a in
                        Label(L("%@: %@ tokens/min agora", a.short, usage.burnRate(a).formatted()), systemImage: "flame.fill")
                            .font(.system(size: 11.5)).foregroundStyle(a.color)
                    }
                }
            }
        }
    }

    private func present(_ bars: [AgentUsageBar]) -> [AgentKind] {
        let used = Set(bars.filter { $0.tokens > 0 }.compactMap(\.agent))
        return AgentKind.allCases.filter(used.contains)
    }

    private func chart(_ h: AgentUsageHistory, _ w: UsageWindow) -> some View {
        let bars = h.bars(w, byAgent: byTool)
        let unit = w.bucket.component
        return VStack(alignment: .leading, spacing: 4) {
            Chart(Array(bars.enumerated()), id: \.offset) { _, b in
                if let a = b.agent {
                    BarMark(x: .value("date", b.start, unit: unit), y: .value("tokens", b.tokens))
                        .foregroundStyle(by: .value("agent", a.name))
                } else {
                    BarMark(x: .value("date", b.start, unit: unit), y: .value("tokens", b.tokens))
                        .foregroundStyle(Color.accentColor.gradient)
                }
            }
            // Na legenda, só as ferramentas que aparecem no gráfico
            .chartForegroundStyleScale(domain: present(bars).map(\.name), range: present(bars).map(\.color))
            .chartLegend(byTool ? .visible : .hidden)
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { Text(Self.tokens(v.as(Int.self) ?? 0)) } } }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: w.bucket == .day ? 7 : 8)) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Date.self) {
                            Text(w.bucket == .day ? d.formatted(.dateTime.day().month(.abbreviated).locale(L10n.locale))
                                                  : d.formatted(.dateTime.month(.abbreviated).year(.twoDigits).locale(L10n.locale)))
                        }
                    }
                }
            }
            .environment(\.locale, L10n.locale)
            .frame(height: 150)
            Text(w.bucket.title).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    private func ranking(_ title: String, _ rows: [(name: String, agent: AgentKind, tokens: Int, cost: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
            let maxT = Double(rows.first?.tokens ?? 1)
            ForEach(rows, id: \.name) { r in
                HStack(spacing: 8) {
                    Circle().fill(r.agent.color).frame(width: 7, height: 7)
                    Text(r.name).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.tokens(r.tokens)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary)
                    if r.cost > 0 { Text(Self.money(r.cost)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.tertiary).frame(width: 54, alignment: .trailing) }
                }
                .background(alignment: .leading) {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3).fill(r.agent.color.opacity(0.1)).frame(width: g.size.width * Double(r.tokens) / maxT)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Modelos no Mac

    private var localModels: some View {
        section(L("Modelos rodando no Mac"), trailing: nil) {
            ForEach(usage.localModels) { m in
                HStack {
                    Image(systemName: "cpu").foregroundStyle(.teal)
                    Text(m.name).font(.system(size: 12.5, weight: .medium))
                    Text(m.app).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    if let b = m.bytes { Text(Fmt.memShort(UInt64(b))).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary) }
                }
            }
        }
    }

    // MARK: Configurar

    private var setup: some View {
        section(L("Configurar"), trailing: nil) {
            let _ = tick
            Text(L("Avisos no notch e notificações quando um agente termina ou precisa de você. Cada ferramenta roda o Menew a cada evento; nada sai do Mac."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            // Só as que estão neste Mac
            ForEach(AgentKind.allCases.filter(\.isInstalled)) { a in
                HStack(spacing: 10) {
                    agentBadge(a)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name).font(.system(size: 12.5, weight: .medium))
                        Text(a.hasHooks ? AgentHooks.configURL(a).path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                                        : L("Sem hooks: o Menew vê o processo e o uso"))
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if !a.hasHooks {
                        EmptyView()
                    } else {
                        switch AgentHooks.status(a) {
                        case .installed:
                            pill(L("Ligado"), .green)
                            Button(L("Desligar")) { confirm = (a, false) }.controlSize(.small)
                        case .outdated:
                            pill(L("Desatualizado"), .orange)
                            Button(L("Atualizar")) { confirm = (a, true) }.controlSize(.small)
                        case .notInstalled:
                            Button(L("Ligar")) { confirm = (a, true) }.controlSize(.small)
                        }
                    }
                }
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            Divider().padding(.vertical, 2)
            Toggle(L("Notificação quando um agente termina (depois de 20 s) ou espera você"), isOn: defaultsBinding(AgentHub.notifyKey, true))
            Toggle(L("Avisar com 75% e 90% de um limite"), isOn: defaultsBinding(AgentUsageStore.alertsKey, true))
            VStack(alignment: .leading, spacing: 2) {
                Toggle(L("Limites do Claude (5 horas e semana)"), isOn: Binding(get: { ClaudePlanLimits.isOn }, set: { usage.setClaudePlan($0) }))
                Text(L("Opcional e desligado: usa o login que o Claude Code guarda nas Chaves para consultar a Anthropic a cada 5 minutos. É a única coisa aqui que usa a internet."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.leading, 20)
            }
        }
        .toggleStyle(.checkbox).font(.system(size: 12.5))
    }

    private var mcp: some View {
        section(L("Servidor MCP"), trailing: AnyView(
            Button(L("Copiar configuração")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(MCPClient.snippet, forType: .string)
                HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
            }.controlSize(.small)
        )) {
            let _ = tick
            Text(L("Deixe seus agentes perguntarem ao Menew: o que você guardou, as atas das reuniões, como está o Mac. Roda no Mac, sem rede."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 8) {
                ForEach(MCPClient.allCases.filter(\.isAvailable)) { c in
                    HStack {
                        Text(c.name).font(.system(size: 12.5, weight: .medium))
                        Spacer()
                        if mcpStatus.busy.contains(c) { ProgressView().controlSize(.mini) }
                        Toggle("", isOn: Binding(get: { mcpStatus.installed[c] ?? false }, set: { mcpStatus.set(c, $0) }))
                            .toggleStyle(.switch).controlSize(.small).labelsHidden().disabled(mcpStatus.busy.contains(c))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }
            }
            if let e = mcpStatus.error { Text(e).font(.system(size: 12)).foregroundStyle(.red) }
            network
            Text(L("O que os agentes podem usar")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
            ForEach(MCPSource.allCases) { s in
                Toggle(isOn: defaultsBinding(s.key, s != .clipboard)) {
                    HStack(spacing: 8) {
                        Image(systemName: s.icon).frame(width: 16).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.title).font(.system(size: 12.5))
                            Text(s.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    /// Para agentes num contêiner (Docker), que não conseguem abrir o Menew do Mac
    @ViewBuilder private var network: some View {
        let on = UserDefaults.standard.bool(forKey: MCPHTTP.enabledKey)
        Toggle(isOn: Binding(get: { on }, set: { setNetwork($0) })) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Acesso para agentes no Docker")).font(.system(size: 12.5))
                Text(L("Só neste Mac, com uma chave. O Menew precisa estar aberto.")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox).padding(.top, 4)
        if on {
            if let e = MCPHTTP.shared.error { Text(e).font(.system(size: 12)).foregroundStyle(.red) }
            let docker = MCPDockerClient.all()
            if !docker.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 8) {
                    ForEach(docker) { c in
                        HStack {
                            Text(c.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Spacer()
                            Toggle("", isOn: Binding(get: { c.isInstalled }, set: { v in
                                mcpStatus.error = c.set(v); tick += 1
                            })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }
                }
            }
            HStack(spacing: 8) {
                Text(MCPHTTP.dockerURL.replacingOccurrences(of: MCPHTTP.token, with: "••••"))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(L("Copiar configuração")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(MCPDockerClient.snippet, forType: .string)
                    HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
                }.controlSize(.small)
                Button(L("Trocar a chave")) {
                    MCPHTTP.resetToken()
                    // Quem o Menew configurou recebe a chave nova
                    for c in MCPDockerClient.all() where c.isInstalled { _ = c.set(true) }
                    tick += 1
                }.controlSize(.small)
                .help(L("Quem tinha a chave antiga perde o acesso"))
            }
        }
    }

    private func setNetwork(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: MCPHTTP.enabledKey)
        if !on { for c in MCPDockerClient.all() where c.isInstalled { _ = c.set(false) } }
        MCPHTTP.shared.sync()
        tick += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tick += 1 }
    }

    private func defaultsBinding(_ key: String, _ def: Bool) -> Binding<Bool> {
        Binding(get: { UserDefaults.standard.object(forKey: key) as? Bool ?? def }, set: { UserDefaults.standard.set($0, forKey: key); tick += 1 })
    }

    // MARK: Peças

    private func section<C: View>(_ title: String, trailing: AnyView?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                trailing
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }

    private func agentBadge(_ a: AgentKind) -> some View {
        Image(systemName: a.icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(a.color.gradient))
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(color.opacity(0.14)))
    }

    private func stat(_ title: String, _ value: String, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).monospacedDigit()
            Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .help(help ?? "")
    }

    /// 1234567 → "1,2 mi" / "1.2M"
    static func tokens(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(L10n.locale))
    }

    static func money(_ v: Double) -> String {
        v.formatted(.currency(code: "USD").precision(.fractionLength(v >= 100 ? 0 : 2)).locale(L10n.locale))
    }
}
