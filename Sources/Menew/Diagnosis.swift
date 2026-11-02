import AppKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Por que meu Mac está lento?": junta memória, CPU, temperatura, disco, bateria e o histórico, aponta o que está
/// fora do normal com regras simples (funciona em qualquer Mac) e, com a Apple Intelligence, explica em palavras simples.
/// Só lê; nada é fechado ou mudado sem você clicar.
@MainActor
enum Diagnosis {
    struct Finding: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let text: String
    }

    struct Snapshot {
        var findings: [Finding]
        /// Os números para o modelo, em inglês (ele segue melhor)
        var facts: String
    }

    /// Nome do app: ajudantes contam no principal, e nomes cortados pelo `top` ("Microsoft Edge H") viram o app aberto
    static func displayName(pid: Int32, command: String) -> String {
        var name = SystemHistory.appName(pid: pid, command: command)
        if NSRunningApplication(processIdentifier: pid)?.bundleURL?.pathExtension != "app" {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
            name = apps.filter { $0.count >= 3 && command.hasPrefix($0) }.max { $0.count < $1.count } ?? name
        }
        return name.replacingOccurrences(of: #"\s+Helper.*$"#, with: "", options: .regularExpression)
    }

    /// Programas em /System ou /usr são do próprio macOS: a sugestão nunca é encerrá-los
    static func isSystem(pid: Int32) -> Bool {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return true }
        let path = String(cString: buf)
        return path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/sbin/")
    }

    static func make(_ m: SystemMonitor, cpuTop: [ProcInfo], memTop rows: [SystemHistory.TopRow]) -> Snapshot {
        // Ajudantes contam no app principal ("Claude Helper (Renderer)" → Claude); nomes que são só versão ficam de fora
        var merged: [String: Double] = [:]
        for r in rows {
            let name = displayName(pid: r.pid, command: r.command)
            guard name.range(of: #"^[0-9.\s]+$"#, options: .regularExpression) == nil else { continue }
            merged[name, default: 0] += r.memMB
        }
        let memTop = merged.sorted { $0.value > $1.value }.map { SystemHistory.TopRow(pid: 0, command: $0.key, cpu: 0, memMB: $0.value, power: 0) }
        var f: [Finding] = []
        var facts: [String] = []
        let memPct = Int(m.memFraction * 100)
        let pressure = m.memPressure == .critical ? "critical" : m.memPressure == .warning ? "high" : "normal"
        facts.append("Memory: \(memPct)% used of \(Fmt.mem(m.memTotal)), pressure \(pressure), swap \(Fmt.bytes(Int64(m.swapUsed)))")
        let bigMem = memTop.prefix(3).map { "\($0.command) \(Fmt.bytes(Int64($0.memMB * 1_048_576)))" }
        if !bigMem.isEmpty { facts.append("Apps using the most memory: " + bigMem.joined(separator: ", ")) }
        if m.memPressure != .normal {
            f.append(Finding(icon: "memorychip", color: m.memPressure == .critical ? .red : .orange,
                             text: L("A memória está sob pressão (%d%% em uso). Os que mais usam: %@.", memPct,
                                     memTop.prefix(3).map(\.command).joined(separator: ", "))))
        } else if m.swapUsed > 4 << 30 {
            f.append(Finding(icon: "memorychip", color: .orange,
                             text: L("O Mac está usando %@ de swap no disco, o que deixa tudo mais lento.", Fmt.bytes(Int64(m.swapUsed)))))
        }

        let cpuPct = Int(m.cpu * 100)
        facts.append("CPU now: \(cpuPct)%")
        let busy = cpuTop.filter { $0.cpu >= 50 && $0.pid != getpid() }
        if !cpuTop.isEmpty { facts.append("Busiest processes: " + cpuTop.prefix(3).map { "\($0.name) \(Int($0.cpu))%" }.joined(separator: ", ")) }
        for p in busy.prefix(2) {
            let name = displayName(pid: p.pid, command: p.name)
            if isSystem(pid: p.pid) {
                facts.append("\(name) is a macOS system process: never suggest quitting it")
                f.append(Finding(icon: "gearshape.2", color: .yellow,
                                 text: L("%@ é um processo do macOS e está usando %d%% da CPU. Costuma passar sozinho em alguns minutos.", name, Int(p.cpu))))
            } else {
                f.append(Finding(icon: "cpu", color: p.cpu >= 90 ? .red : .orange, text: L("%@ está usando %d%% da CPU.", name, Int(p.cpu))))
            }
        }
        let lastHour = SystemHistory.shared.samples.filter { $0.t > Date().addingTimeInterval(-3600) }
        if lastHour.count >= 20 {
            let avg = lastHour.map(\.cpu).reduce(0, +) / Double(lastHour.count)
            facts.append("CPU average in the last hour: \(Int(avg * 100))%")
            if avg > 0.6 { f.append(Finding(icon: "chart.xyaxis.line", color: .orange, text: L("A CPU ficou em %d%% em média na última hora.", Int(avg * 100)))) }
        }

        if let chip = Sensors.shared.chip { facts.append("Chip temperature: \(Int(chip)) °C") }
        facts.append("Thermal state: \(["nominal", "fair", "serious", "critical"][min(3, m.thermal.rawValue)])")
        if m.thermal == .serious || m.thermal == .critical {
            f.append(Finding(icon: "thermometer.high", color: .red, text: L("O Mac está quente e o macOS reduziu a velocidade para esfriar.")))
        }

        if m.diskTotal > 0 {
            let freePct = Double(m.diskFree) / Double(m.diskTotal)
            facts.append("Disk: \(Fmt.bytes(m.diskFree)) free of \(Fmt.bytes(m.diskTotal))")
            if freePct < 0.1 || m.diskFree < 15_000_000_000 {
                f.append(Finding(icon: "internaldrive", color: .orange, text: L("O disco está quase cheio (%@ livres). Pouco espaço deixa o Mac lento.", Fmt.bytes(m.diskFree))))
            }
        }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            facts.append("Low Power Mode: on")
            f.append(Finding(icon: "battery.25percent", color: .yellow, text: L("O Modo Pouca Energia está ligado e reduz o desempenho.")))
        }
        let days = Int(m.uptime / 86_400)
        facts.append("Uptime: \(days) days")
        if days >= 14 { f.append(Finding(icon: "arrow.clockwise", color: .yellow, text: L("O Mac está ligado há %d dias. Reiniciar costuma ajudar.", days))) }

        if f.isEmpty { f.append(Finding(icon: "checkmark.seal.fill", color: .green, text: L("Nada fora do normal agora. Se a lentidão for num app, ele pode estar esperando a internet ou o disco."))) }
        // O que as regras acharam também vai para o modelo, para a explicação não esquecer nada
        facts.append("Problems found: " + f.map(\.text).joined(separator: " | "))
        return Snapshot(findings: f, facts: facts.joined(separator: "\n"))
    }

    /// Explicação curta do modelo, aos poucos
    static func explain(_ facts: String, onPartial: @escaping @MainActor (String) -> Void) async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let language = Locale(identifier: "en").localizedString(forLanguageCode: L10n.current.rawValue) ?? "English"
            let session = LanguageModelSession(model: .default, instructions: """
                You explain to a non-technical person why their Mac may feel slow, using only the facts given. \
                Write two or three short sentences about the problems found, then up to three concrete suggestions tied to them \
                (name the apps), as a list starting with "• ". \
                If nothing looks wrong, say so plainly. Never invent numbers. Never suggest quitting macOS system processes. Do not mention anything that is not in the facts. Write in \(language).
                """)
            for try await snapshot in session.streamResponse(to: "Facts about the Mac right now:\n" + facts) {
                await onPartial(snapshot.content)
            }
            return
        }
        #endif
        throw CancellationError()
    }
}

@MainActor
final class DiagnosisModel: ObservableObject {
    @Published var findings: [Diagnosis.Finding] = []
    @Published var explanation = ""
    @Published var loading = true
    @Published var thinking = false
    @Published var aiNote: String?

    func run(_ m: SystemMonitor) {
        loading = true
        explanation = ""
        aiNote = nil
        Sensors.shared.refresh()
        Task {
            let (cpu, mem) = await Task.detached(priority: .userInitiated) {
                (SystemMonitor.readTopProcesses(),
                 SystemHistory.parseTop(Shell.run("/usr/bin/top", ["-l", "1", "-n", "8", "-o", "mem", "-stats", "pid,command,cpu,mem,power"]), lastSample: false))
            }.value
            let snap = Diagnosis.make(m, cpuTop: cpu, memTop: mem)
            findings = snap.findings
            loading = false
            guard AIFeature.diagnosis.isOn else { return }
            if let reason = AIText.unavailableReason {
                aiNote = L("Com a Apple Intelligence, o Menew também explica em palavras simples. (%@)", reason)
                return
            }
            thinking = true
            do {
                try await Diagnosis.explain(snap.facts) { self.explanation = $0 }
            } catch {
                aiNote = L("A IA não conseguiu responder")
            }
            thinking = false
        }
    }
}

@MainActor
final class DiagnosisWindow {
    static let shared = DiagnosisWindow()
    let model = DiagnosisModel()
    private var window: NSWindow?

    func show(_ m: SystemMonitor) {
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        let w = window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = L("Por que meu Mac está lento?")
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: DiagnosisView(model: model, monitor: m))
            w.center()
            return w
        }()
        window = w
        model.run(m)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct DiagnosisView: View {
    @ObservedObject var model: DiagnosisModel
    let monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Por que meu Mac está lento?")).font(.system(size: 17, weight: .bold))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.loading {
                            HStack { ProgressView().controlSize(.small); Text(L("Olhando o Mac…")).font(.system(size: 12.5)) }.padding(12)
                        }
                        ForEach(Array(model.findings.enumerated()), id: \.element.id) { i, f in
                            if i > 0 { RowDivider() }
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: f.icon).foregroundStyle(f.color).frame(width: 18)
                                Text(f.text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                        }
                    }
                    .glass()
                    if model.thinking || !model.explanation.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "apple.intelligence").foregroundStyle(.pink)
                                Text(L("Em palavras simples")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                if model.thinking { ProgressView().controlSize(.mini) }
                            }
                            Text(model.explanation.isEmpty ? L("Pensando…") : model.explanation)
                                .font(.system(size: 12.5)).lineSpacing(2).textSelection(.enabled)
                                .foregroundStyle(model.explanation.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12).glass()
                    }
                    if let note = model.aiNote {
                        Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Text(L("No seu Mac, sem internet")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                PillButton(title: L("Monitor de Atividade"), icon: "chart.bar.xaxis") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                PillButton(title: L("Analisar de novo"), icon: "arrow.clockwise", primary: true) { model.run(monitor) }
                    .disabled(model.loading || model.thinking)
            }
        }
        .padding(20).padding(.top, 18)
        .frame(minWidth: 460, minHeight: 400)
        .background(Theme.windowFill)
    }
}
