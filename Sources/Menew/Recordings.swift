import AppKit
import AVFoundation
import ScreenCaptureKit
import Speech
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Gravações: um atalho começa e para; o Mac transcreve sozinho e a IA monta a ata (resumo, decisões, tarefas com
/// responsável e etiquetas). Microfone e som do Mac vão para arquivos separados, então a transcrição sabe o que foi
/// você ("Eu") e o que veio da chamada ("Outros"). Tudo fica numa pasta no Mac.
struct Recording: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case recording, transcribing, summarizing, ready, failed }

    struct Task: Codable, Identifiable, Equatable {
        var id = UUID()
        var text: String
        var owner: String?
        var due: String?
        var done = false
        var reminder = false
    }

    /// Um assunto da reunião e o que foi dito sobre ele
    struct Topic: Codable, Identifiable, Equatable {
        var id = UUID()
        var title: String
        var points: [String]
    }

    var id = UUID()
    var date = Date()
    var duration: TimeInterval = 0
    var title: String
    var status: Status = .recording
    var micFile: String?
    var systemFile: String?
    var locale: String
    var transcript = ""
    var summary = ""
    var decisions: [String] = []
    var tasks: [Task] = []
    var tags: [String] = []
    var people: [String] = []
    /// A nota com a ata (Notas › #gravação); opcional para gravações antigas
    var noteID: UUID?
    /// O vídeo, quando veio de uma gravação de tela com som
    var video: String?
    // Ata detalhada (opcionais: gravações antigas não têm; "Refazer a ata" preenche)
    var theme: String?
    var topics: [Topic]?
    var nextSteps: [String]?
    var remarks: [String]?

    var haystack: String {
        PaletteSearch.fold([title, theme ?? "", summary, (topics ?? []).map { $0.title + " " + $0.points.joined(separator: " ") }.joined(separator: " "),
                            decisions.joined(separator: " "), tasks.map(\.text).joined(separator: " "),
                            tags.joined(separator: " "), people.joined(separator: " "), transcript].joined(separator: " "))
    }

    /// A ata em Markdown, para virar nota ou ir para o clipboard
    var markdown: String {
        var out = "# \(title)\n\n\(date.formatted(date: .abbreviated, time: .shortened))"
        if duration > 0 { out += " · \(RecordingStore.clock(duration))" }
        // #gravação junta todas as atas nas Notas
        out += "  #" + L("gravação").replacingOccurrences(of: " ", with: "-")
        if !tags.isEmpty { out += " " + tags.map { "#" + $0.replacingOccurrences(of: " ", with: "-") }.joined(separator: " ") }
        func list(_ title: String, _ items: [String]?) {
            guard let items, !items.isEmpty else { return }
            out += "\n\n## \(title)\n\n" + items.map { "- \($0)" }.joined(separator: "\n")
        }
        if let theme, !theme.isEmpty { out += "\n\n## \(L("Tema central"))\n\n\(theme)" }
        if !summary.isEmpty { out += "\n\n## \(L("Resumo"))\n\n\(summary)" }
        if !people.isEmpty { out += "\n\n## \(L("Pessoas citadas"))\n\n" + people.joined(separator: ", ") }
        if let topics, !topics.isEmpty {
            out += "\n\n## \(L("Tópicos discutidos"))"
            for t in topics { out += "\n\n### \(t.title)\n\n" + t.points.map { "- \($0)" }.joined(separator: "\n") }
        }
        list(L("Decisões"), decisions)
        if !tasks.isEmpty {
            // Tabela: fica legível colada num e-mail, no Notion ou no Confluence
            let cell = { (s: String) in s.replacingOccurrences(of: "|", with: "/") }
            out += "\n\n## \(L("Tarefas"))\n\n| \(L("Tarefa")) | \(L("Responsável")) | \(L("Prazo")) |\n|---|---|---|\n"
            out += tasks.map { t in
                "| \(t.done ? "✓ " : "")\(cell(t.text)) | \(cell(t.owner ?? "—")) | \(cell(t.due ?? L("A definir"))) |"
            }.joined(separator: "\n")
        }
        list(L("Próximos passos"), nextSteps)
        list(L("Observações"), remarks)
        if !transcript.isEmpty { out += "\n\n## \(L("Transcrição"))\n\n\(transcript)" }
        return out
    }
}

@MainActor
final class RecordingStore: NSObject, ObservableObject {
    static let shared = RecordingStore()
    static let shortcutKey = "shortcutRecording"
    static let autoRemindersKey = "recordingsAutoReminders"
    static let sourceKey = "recordingsSource"
    static let notesKey = "recordingsToNotes"
    /// Também salvar cada ata como nota (desligado: as gravações já aparecem como uma pasta nas Notas)
    static var toNotes: Bool { UserDefaults.standard.bool(forKey: notesKey) }

    /// O que gravar: o som do Mac e o microfone (uma chamada), só o som do Mac (você só ouve) ou só o microfone
    enum Source: String, CaseIterable, Identifiable {
        case both, system, mic
        var id: String { rawValue }
        var title: String {
            switch self {
            case .both: L("Som do Mac e microfone")
            case .system: L("Só o som do Mac")
            case .mic: L("Só o microfone")
            }
        }
        var short: String {
            switch self {
            case .both: L("Som + mic")
            case .system: L("Som do Mac")
            case .mic: L("Microfone")
            }
        }
        var icon: String {
            switch self {
            case .both: "person.2.wave.2"
            case .system: "speaker.wave.2"
            case .mic: "mic"
            }
        }
    }

    @Published private(set) var items: [Recording] = []
    @Published var selectedID: UUID?
    @Published var query = ""
    @Published var tag: String?
    @Published private(set) var recordingID: UUID?
    @Published private(set) var startedAt = Date()
    @Published var level: Float = 0
    /// A ata de uma reunião longa demora (minutos): em que parte a IA está, para a tela mostrar
    @Published private(set) var minutesProgress: [UUID: (done: Int, total: Int)] = [:]
    private(set) var dir: URL?
    private var demo = false

    private var engine: AVAudioEngine?
    private var micWriter: AudioFileWriter?
    private var systemWriter: AudioFileWriter?
    private var stream: SCStream?
    private let systemOutput = RecordingSystemOutput()
    /// Só um símbolo de parar na barra de menus enquanto grava (nada no meio da tela, bom para compartilhar a tela)
    private var stopItem: NSStatusItem?

    var isRecording: Bool { recordingID != nil }
    var source: Source { Source(rawValue: UserDefaults.standard.string(forKey: Self.sourceKey) ?? "") ?? .both }

    func load(base: URL) {
        let d = base.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        dir = d
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: d.appendingPathComponent("recordings.json")), let saved = try? dec.decode([Recording].self, from: data) {
            // Gravação interrompida (o app fechou no meio): fica como falha, com o áudio que deu tempo de salvar
            items = saved.map { var r = $0; if r.status != .ready { r.status = .failed }; return r }
        }
    }

    private func save() {
        guard !demo, let dir else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(items).write(to: dir.appendingPathComponent("recordings.json"), options: .atomic)
    }

    func update(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        save()
    }

    var allTags: [String] {
        var count: [String: Int] = [:]
        for r in items { for t in r.tags { count[t, default: 0] += 1 } }
        return count.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
    }

    var filtered: [Recording] {
        let words = PaletteSearch.fold(query).split(separator: " ").map(String.init)
        return items.filter { r in
            (tag == nil || r.tags.contains(tag!)) && (words.isEmpty || words.allSatisfy { r.haystack.contains($0) })
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: Gravar

    func toggle() { isRecording ? stop() : start() }

    func start(source: Source? = nil) {
        guard !isRecording, let dir else { return }
        let src = source ?? self.source
        // A escolha vira o padrão do atalho
        UserDefaults.standard.set(src.rawValue, forKey: Self.sourceKey)
        var rec = Recording(title: L("Gravação de %@", Date().formatted(date: .abbreviated, time: .shortened)),
                            locale: Transcriber.preferred.first?.code ?? "pt-BR")
        let micURL = dir.appendingPathComponent("\(rec.id.uuidString)-mic.m4a")
        let sysURL = dir.appendingPathComponent("\(rec.id.uuidString)-system.m4a")
        if src != .system {
            do {
                let e = AVAudioEngine()
                let input = e.inputNode
                let writer = try AudioFileWriter(url: micURL)
                input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0)) { [weak writer] buffer, _ in
                    writer?.write(buffer)
                    let peak = Self.peak(buffer)
                    DispatchQueue.main.async { MainActor.assumeIsolated { RecordingStore.shared.level = peak } }
                }
                try e.start()
                engine = e
                micWriter = writer
                rec.micFile = micURL.lastPathComponent
            } catch {
                HUD.show(icon: "mic.slash.fill", color: .orange, text: L("Permita o microfone para o Menew em Ajustes do Sistema › Privacidade"), duration: 3)
                return
            }
        }
        if src != .mic { rec.systemFile = sysURL.lastPathComponent }
        recordingID = rec.id
        startedAt = Date()
        showStopItem()
        items.insert(rec, at: 0)
        save()
        NotchCenter.shared.update()
        HUD.show(icon: "record.circle", color: .red, text: L("Gravando: %@", src.short))
        // O som do Mac (a outra ponta de uma chamada, um vídeo) num arquivo à parte
        guard src != .mic, let writer = try? AudioFileWriter(url: sysURL) else { return }
        systemWriter = writer
        systemOutput.writer = writer
        systemOutput.meter = src == .system
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { throw CocoaError(.featureUnsupported) }
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48_000
                config.channelCount = 1
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let s = SCStream(filter: SCContentFilter(display: display, excludingApplications: [], exceptingWindows: []), configuration: config, delegate: nil)
                try s.addStreamOutput(systemOutput, type: .audio, sampleHandlerQueue: systemOutput.queue)
                try await s.startCapture()
                stream = s
            } catch {
                systemWriter = nil
                systemOutput.writer = nil
                update(rec.id) { $0.systemFile = nil }
                HUD.show(icon: "speaker.slash.fill", color: .orange,
                         text: L("Permita a gravação de tela e áudio do sistema para o Menew em Ajustes do Sistema › Privacidade."), duration: 3)
                // Só o som do Mac e não deu: não há o que gravar
                if src == .system { recordingID = nil; hideStopItem(); delete(rec.id); NotchCenter.shared.update() }
            }
        }
    }

    /// O som de uma gravação de tela vira uma gravação com ata, ligada ao vídeo
    func importScreenRecording(mic: URL?, system: URL?, video: URL, duration: TimeInterval) {
        var r = Recording(title: video.deletingPathExtension().lastPathComponent, locale: Transcriber.preferred.first?.code ?? "pt-BR")
        r.date = Date().addingTimeInterval(-duration)
        r.duration = duration
        r.micFile = mic?.lastPathComponent
        r.systemFile = system?.lastPathComponent
        r.video = video.path
        r.status = .transcribing
        items.insert(r, at: 0)
        save()
        Task { await process(r.id) }
    }

    func stop() {
        guard let id = recordingID else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        micWriter?.close()
        micWriter = nil
        systemOutput.writer = nil
        systemWriter?.close()
        systemWriter = nil
        if let s = stream { Task { try? await s.stopCapture() } }
        stream = nil
        let duration = Date().timeIntervalSince(startedAt)
        recordingID = nil
        hideStopItem()
        level = 0
        NotchCenter.shared.update()
        update(id) { $0.duration = duration; $0.status = .transcribing }
        HUD.show(icon: "waveform", color: .secondary, text: L("Transcrevendo a gravação…"))
        Task { await process(id) }
    }

    private func showStopItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = item.button {
            let img = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: L("Parar a gravação"))
            img?.isTemplate = true
            b.image = img
            b.toolTip = L("Gravando · clique para parar")
            b.target = self
            b.action = #selector(stopFromMenuBar)
        }
        stopItem = item
    }

    private func hideStopItem() {
        if let stopItem { NSStatusBar.system.removeStatusItem(stopItem) }
        stopItem = nil
    }

    @objc private func stopFromMenuBar() { stop() }

    nonisolated static func peak(_ b: AVAudioPCMBuffer) -> Float {
        guard let ch = b.floatChannelData?[0] else { return 0 }
        var m: Float = 0
        for i in stride(from: 0, to: Int(b.frameLength), by: 8) { m = max(m, abs(ch[i])) }
        return m
    }

    // MARK: Transcrever e resumir

    func process(_ id: UUID) async {
        guard let r = items.first(where: { $0.id == id }), let dir else { return }
        update(id) { $0.status = .transcribing }
        let urls = [(r.micFile, L("Eu")), (r.systemFile, L("Outros"))].compactMap { f, who in f.map { (dir.appendingPathComponent($0), who) } }
            .filter { FileManager.default.fileExists(atPath: $0.0.path) }
        var segments: [(Double, String, String)] = []
        for (url, who) in urls {
            if let segs = try? await Self.segments(url, locale: r.locale) {
                segments += segs.map { ($0.0, who, $0.1) }
            }
        }
        // Só um lado com fala: sem rótulos
        let speakers = Set(segments.map(\.1))
        let transcript = segments.sorted { $0.0 < $1.0 }
            .map { speakers.count > 1 ? "\($0.1): \($0.2)" : $0.2 }
            .joined(separator: "\n")
        update(id) { $0.transcript = transcript }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            update(id) { $0.status = .ready; $0.summary = L("Nenhuma fala reconhecida.") }
            return
        }
        guard AIText.unavailableReason == nil else {
            update(id) { $0.status = .ready }
            if Self.toNotes { syncNote(id) }
            HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Transcrição pronta"))
            return
        }
        update(id) { $0.status = .summarizing }
        let notes = await Self.minutes(transcript) { [weak self] done, total in self?.minutesProgress[id] = (done, total) }
        minutesProgress[id] = nil
        if let notes {
            update(id) {
                if !notes.title.isEmpty { $0.title = notes.title }
                $0.summary = notes.summary
                $0.decisions = notes.decisions
                $0.tasks = notes.tasks
                $0.tags = notes.tags
                $0.people = notes.people
                $0.theme = notes.theme.isEmpty ? nil : notes.theme
                $0.topics = notes.topics.isEmpty ? nil : notes.topics
                $0.nextSteps = notes.nextSteps.isEmpty ? nil : notes.nextSteps
                $0.remarks = notes.remarks.isEmpty ? nil : notes.remarks
            }
        }
        update(id) { $0.status = .ready }
        if Self.toNotes { syncNote(id) }
        HUD.show(icon: "checkmark.circle.fill", color: .green, text: L("Ata pronta"))
        if UserDefaults.standard.bool(forKey: Self.autoRemindersKey) { await remindMine(id) }
    }

    /// Trechos com o segundo em que começam (macOS 26: o transcritor novo, sem pedir permissão)
    static func segments(_ url: URL, locale: String) async throws -> [(Double, String)] {
        #if canImport(Speech)
        if #available(macOS 26, *) {
            let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) ?? Locale(identifier: locale)
            let transcriber = SpeechTranscriber(locale: loc, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await req.downloadAndInstall() }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let file = try AVAudioFile(forReading: url)
            async let collected: [(Double, String)] = {
                var out: [(Double, String)] = []
                for try await r in transcriber.results {
                    let t = String(r.text.characters).trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { out.append((r.range.start.seconds, t)) }
                }
                return out
            }()
            if let end = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await collected
        }
        #endif
        let text = try await Transcriber.transcribe(url, locale: locale)
        return text.isEmpty ? [] : [(0, text)]
    }

    struct Minutes {
        var title = "", summary = "", decisions: [String] = [], tasks: [Recording.Task] = [], tags: [String] = [], people: [String] = []
        var theme = "", topics: [Recording.Topic] = [], nextSteps: [String] = [], remarks: [String] = []
    }

    /// A ata. A transcrição é lida inteira, em partes (o modelo do Mac lê pouco texto de cada vez): cada parte vira
    /// tópicos com o que foi dito de verdade, decisões, tarefas e próximos passos; depois, uma passada sobre os tópicos
    /// escreve o título, o tema central e o resumo.
    static func minutes(_ transcript: String, progress: ((Int, Int) -> Void)? = nil) async -> Minutes? {
        // Fala curta (um teste, um lembrete de 5 segundos): só um título com o que foi dito, sem ata inventada
        let spoken = transcript.split(whereSeparator: \.isNewline).map { line -> String in
            let t = String(line)
            if let r = t.range(of: ": "), t.distance(from: t.startIndex, to: r.lowerBound) < 12 { return String(t[r.upperBound...]) }
            return t
        }.joined(separator: " ")
        if spoken.split(separator: " ").count < 30 {
            return Minutes(title: String(spoken.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).prefix(70)))
        }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let me = AboutMe.context()
            let parts = chunks(transcript)
            var topics: [Recording.Topic] = []
            var decisions: [String] = [], steps: [String] = [], remarks: [String] = [], people: [String] = []
            var candidates: [(task: MinuteTask, source: String)] = []
            for (i, part) in parts.enumerated() {
                progress?(i + 1, parts.count)
                let session = LanguageModelSession(instructions: """
                    You are a professional minute-taker writing detailed, faithful minutes from part of a meeting transcript. \
                    "Eu" or "Me" is the user; "Outros" or "Others" are the other people. Group what was said into topics, in the \
                    order they came up. For each topic, write the points that were said: facts, numbers, places, names, problems, \
                    options, concerns, explanations and conclusions. Write each point as one clean sentence in the third person, \
                    in the style of formal minutes ("Foi apresentado...", "Davi explicou que..."), never copying the speech word \
                    for word and never in the first person. The transcript comes from speech recognition: fix obvious recognition \
                    errors and ignore filler, greetings and small talk. In sentences, call the user by their name (below), \
                    never "Eu". Never invent anything that was not said. \
                    Write in the same language as the transcript. \
                    Topics are subjects of the conversation, never "Tasks", "Decisions" or "Next steps". \
                    Only list a decision when something was actually decided and a next step when something was planned. \
                    Empty lists are fine. \
                    \(me)
                    """)
                let prompt = "Transcript, part \(i + 1) of \(parts.count):\n\(part)"
                if let c = try? await session.respond(to: prompt, generating: MeetingNotes.self).content {
                    mergeTopics(&topics, c.topics.filter { !isSectionTitle($0.title) }.map { ($0.title, $0.points) })
                    decisions += c.decisions
                    steps += c.nextSteps
                    remarks += c.remarks
                    people += c.people
                }
                // As tarefas numa conversa à parte, só com elas: junto com o resto, o modelo esquecia algumas e errava o dono
                let taskSession = LanguageModelSession(instructions: """
                    You list the action items from part of a meeting transcript. "Eu" or "Me" is the user; "Outros" or "Others" \
                    are the other people, who may be several. A task is something someone was asked to do or said that they or \
                    another person will do, including in a recap at the end. The owner is the person who will do it: the name \
                    said in the request or the recap, or the person who said "I will". When someone in "Outros" says "I will" \
                    right after being asked by name, the owner is that name. Only use "Eu" when the user is the one doing it. \
                    Leave the deadline empty unless a date or a time limit was actually said for that task; never repeat \
                    one deadline for every task. Write each task as a short, clear action starting with a verb, not as a \
                    quote. Never invent tasks. Same language as the transcript. \
                    \(me)
                    """)
                if let t = try? await taskSession.respond(to: prompt, generating: MeetingTasks.self).content {
                    candidates += t.tasks.map { ($0, part) }
                }
            }
            guard !topics.isEmpty || !candidates.isEmpty else { return nil }

            // Visão geral a partir dos tópicos (cabem no modelo mesmo numa reunião longa)
            let outline = topics.map { t in "## \(t.title)\n" + t.points.prefix(5).map { "- \($0)" }.joined(separator: "\n") }
                .joined(separator: "\n\n")
            let overviewSession = LanguageModelSession(instructions: """
                You write the header of formal meeting minutes from the notes below: impersonal, in the third person, never in \
                the first person. Same language as the notes. Be specific to what was discussed; never invent anything. \(me)
                """)
            let o = try? await overviewSession.respond(
                to: "Notes:\n\(String(outline.prefix(6000)))\n\nDecisions:\n\(dedupe(decisions).prefix(10).map { "- \($0)" }.joined(separator: "\n"))",
                generating: MeetingOverview.self).content

            // "não especificado", "Outros" e o próprio usuário não são informação
            let meNames = [L("Eu"), L("Outros"), "eu", "outros", "me", "others", AboutMe.name] + AboutMe.aliases
            // Tarefa que só repete o que foi dito não é tarefa
            let said = PaletteSearch.fold(spoken)
            // Sem nenhuma palavra de pedido ou compromisso, não há tarefa (uma reflexão em voz alta, por exemplo)
            let cues = ["vou ", "vamos ", "vai ", "fica responsavel", "fico responsavel", "precisa", "preciso", "temos que", "tem que", "pode ",
                        "consegue", "por favor", "ate ", "combinado", "reviso", "mando", "envio", "faco", "fecha ", "lembrar", "prepar", "ficou de",
                        "i'll", "we'll", "will ", "need", "can you", "please", "should", "must", "by friday", "let's", "going to",
                        "ich werde", "wir werden", "bitte", "muss", "bis ", "voy a", "vamos a", "necesito", "puedes", "hay que",
                        "我会", "我们会", "需要", "请", "要"]
            let hasCue = cues.contains { said.contains($0) }
            var tasks: [Recording.Task] = []
            var seen: [String] = []
            for (t, source) in candidates where hasCue {
                let f = PaletteSearch.fold(t.text)
                // Tarefa que vira um parágrafo é a fala copiada, não uma ação
                guard f.count >= 6, t.text.count <= 180, !(said.count < 200 && (said.contains(f) || f.contains(said))),
                      !seen.contains(where: { similar($0, f) }) else { continue }
                // Segunda opinião, contra o trecho de onde a tarefa veio: alguém pediu ou prometeu isso mesmo?
                let judge = LanguageModelSession(instructions: "You check meeting minutes against a transcript. A task is real if someone asked for it, agreed to do it, or said that they or another person will do it. Reflections, feelings and descriptions are not tasks.")
                let q = "Transcript:\n\(String(source.prefix(6000)))\n\nIs this a real task from the transcript: \"\(t.text)\"?"
                guard let v = try? await judge.respond(to: q, generating: TaskCheck.self).content, v.askedOrPromised else { continue }
                seen.append(f)
                tasks.append(Recording.Task(text: t.text, owner: meaningful(t.owner), due: meaningful(t.due)))
            }
            let names = dedupe(people + (o?.people ?? [])).filter { p in !meNames.contains { PaletteSearch.fold($0) == PaletteSearch.fold(p) } }
            return Minutes(title: String((o?.title ?? topics.first?.title ?? "").prefix(90)),
                           summary: o?.summary ?? "",
                           decisions: Array(dedupe(decisions.filter { !isNonItem($0) }).prefix(12)),
                           tasks: Array(tasks.prefix(15)),
                           tags: Array((o?.tags ?? []).prefix(5)).map { $0.lowercased() },
                           people: Array(names.prefix(12)),
                           theme: o?.theme ?? "",
                           topics: Array(topics.prefix(12)),
                           nextSteps: Array(dedupe(steps.filter { !isNonItem($0) }).prefix(10)),
                           remarks: Array(dedupe(remarks.filter { !isNonItem($0) }).prefix(8)))
        }
        #endif
        return nil
    }

    /// Partes de até `size` caracteres, cortadas entre falas (nunca no meio de uma linha, se der)
    nonisolated static func chunks(_ text: String, size: Int = 6000) -> [String] {
        var out: [String] = [], current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = String(line)
            // Uma fala enorme sem quebra (só um lado gravado): corta por tamanho
            while line.count > size {
                if !current.isEmpty { out.append(current); current = "" }
                out.append(String(line.prefix(size)))
                line = String(line.dropFirst(size))
            }
            if current.count + line.count + 1 > size, !current.isEmpty { out.append(current); current = "" }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Junta tópicos de partes diferentes que falam do mesmo assunto, na ordem em que apareceram
    nonisolated static func mergeTopics(_ topics: inout [Recording.Topic], _ new: [(String, [String])], maxPoints: Int = 8) {
        for (title, points) in new {
            let clean = dedupe(points.compactMap { meaningful($0) })
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !clean.isEmpty else { continue }
            let key = PaletteSearch.fold(t)
            if let i = topics.firstIndex(where: { let k = PaletteSearch.fold($0.title); return k == key || k.contains(key) || key.contains(k) }) {
                topics[i].points = Array(dedupe(topics[i].points + clean).prefix(maxPoints))
            } else {
                topics.append(Recording.Topic(title: t, points: Array(clean.prefix(maxPoints))))
            }
        }
    }

    /// Mesma ideia com outras palavras: um texto contido no outro, ou a maior parte das palavras importantes em comum
    /// ("Preparar a conta de retorno" ~ "Preparar uma conta simples de retorno do piloto")
    nonisolated static func similar(_ a: String, _ b: String) -> Bool {
        let fa = PaletteSearch.fold(a), fb = PaletteSearch.fold(b)
        if fa == fb || fa.contains(fb) || fb.contains(fa) { return true }
        func words(_ s: String) -> Set<String> { Set(s.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 }) }
        let wa = words(fa), wb = words(fb)
        guard min(wa.count, wb.count) >= 2 else { return false }
        return Double(wa.intersection(wb).count) / Double(min(wa.count, wb.count)) >= 0.75
    }

    /// "Não foi tomada nenhuma decisão": o modelo às vezes preenche a lista dizendo que ela está vazia
    nonisolated static func isNonItem(_ s: String) -> Bool {
        let f = PaletteSearch.fold(s)
        let empty = ["nao foi tomad", "nenhuma decisao", "nao houve decis", "nao houve nenhum", "nao pode ser registrad", "sem decis",
                     "no decision", "no formal decision", "nothing was decided", "none were made", "keine entscheidung",
                     "ninguna decision", "no se tomo", "没有做出", "无决定"]
        return meaningful(s) == nil || empty.contains { f.contains($0) }
    }

    /// Um "tópico" que na verdade é uma seção da ata (o modelo às vezes devolve "Tarefas" como assunto)
    nonisolated static func isSectionTitle(_ title: String) -> Bool {
        let f = PaletteSearch.fold(title).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        let sections = ["tarefas", "tasks", "action items", "decisoes", "decisions", "proximos passos", "next steps", "recapitulacao",
                        "recap", "resumo", "summary", "encerramento", "aufgaben", "entscheidungen", "nachste schritte", "tareas",
                        "decisiones", "proximos pasos", "任务", "决定", "后续步骤"]
        return sections.contains(f)
    }

    /// Sem repetidos: a mesma ideia (sem acento e sem maiúsculas) só uma vez; fica a versão mais completa
    nonisolated static func dedupe(_ items: [String]) -> [String] {
        var out: [String] = []
        for item in items {
            let s = item.trimmingCharacters(in: .whitespacesAndNewlines)
            let f = PaletteSearch.fold(s)
            guard !f.isEmpty else { continue }
            if let i = out.firstIndex(where: { similar($0, s) }) {
                if s.count > out[i].count { out[i] = s }
            } else {
                out.append(s)
            }
        }
        return out
    }

    // MARK: Lembretes e notas

    /// Cria no app Lembretes uma tarefa (com o nome da gravação nas notas do lembrete)
    func remind(_ recID: UUID, _ taskID: UUID) async {
        guard let r = items.first(where: { $0.id == recID }), let t = r.tasks.first(where: { $0.id == taskID }) else { return }
        await QuickReminder.create(.init(title: t.text, due: nil, hasTime: false))
        update(recID) { rec in if let i = rec.tasks.firstIndex(where: { $0.id == taskID }) { rec.tasks[i].reminder = true } }
    }

    /// As tarefas que são suas (dono vazio, "Eu" ou o seu nome)
    func remindMine(_ recID: UUID) async {
        guard let r = items.first(where: { $0.id == recID }) else { return }
        for t in r.tasks where !t.reminder && AboutMe.isMe(t.owner) { await remind(recID, t.id) }
    }

    func saveAsNote(_ id: UUID) {
        syncNote(id)
        if let note = items.first(where: { $0.id == id })?.noteID { (NSApp.delegate as? AppDelegate)?.openNote(note) }
    }

    /// Cria a nota da ata, ou atualiza a que já existe (sem duplicar)
    func syncNote(_ id: UUID) {
        guard !demo, let r = items.first(where: { $0.id == id }), let notes = (NSApp.delegate as? AppDelegate)?.notes else { return }
        if let nid = r.noteID, notes.note(nid) != nil {
            notes.setText(r.markdown, of: nid)
        } else {
            let nid = notes.create(text: r.markdown)
            update(id) { $0.noteID = nid }
        }
    }

    func delete(_ id: UUID) {
        guard let r = items.first(where: { $0.id == id }) else { return }
        if let dir { for f in [r.micFile, r.systemFile].compactMap({ $0 }) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) } }
        items.removeAll { $0.id == id }
        save()
    }

    func audioURL(_ r: Recording) -> URL? {
        guard let dir else { return nil }
        return (r.micFile ?? r.systemFile).map { dir.appendingPathComponent($0) }
    }

    nonisolated static func clock(_ s: TimeInterval) -> String {
        let t = Int(s)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: Exemplo

    func showDemo() {
        demo = true
        let now = Date()
        var a = Recording(title: L("Alinhamento do lançamento"), locale: "pt-BR")
        a.date = now.addingTimeInterval(-2 * 3600); a.duration = 1840; a.status = .ready
        a.summary = L("O lançamento fica para quinta. A Ana revisa o site até quarta e o Bruno fecha os textos. Falta decidir o preço do plano Pro.")
        a.decisions = [L("Lançar na quinta às 10h"), L("Manter o app grátis, sem anúncios")]
        a.tasks = [Recording.Task(text: L("Revisar o site em todos os idiomas"), owner: "Ana", due: L("quarta")),
                   Recording.Task(text: L("Fechar os textos da loja"), owner: "Bruno"),
                   Recording.Task(text: L("Preparar a lista de novidades"), owner: L("Eu"), reminder: true)]
        a.tags = [L("lançamento"), "menew", L("site")]; a.people = ["Ana", "Bruno"]
        a.theme = L("Data e preparação do lançamento da versão nova, com o site e os textos da loja.")
        a.topics = [
            Recording.Topic(title: L("Data do lançamento"), points: [
                L("A data ficou para quinta às 10h, depois que o build passou nos testes."),
                L("A Ana lembrou que o site precisa estar no ar antes do anúncio.")]),
            Recording.Topic(title: L("Site e textos da loja"), points: [
                L("O site ainda tem páginas sem tradução para alemão e chinês."),
                L("O Bruno fecha os textos da loja; as capturas novas já estão prontas.")]),
            Recording.Topic(title: L("Preço do plano Pro"), points: [
                L("Ficou em aberto: duas opções em discussão, mensal ou pagamento único."),
                L("Ninguém quer anúncios no app grátis.")]),
        ]
        a.nextSteps = [L("Revisar a ata na quarta e confirmar o anúncio"), L("Decidir o preço do Pro na próxima reunião")]
        a.remarks = [L("O lançamento depende do site revisado em todos os idiomas.")]
        a.transcript = L("Eu: Então fica para quinta?\nOutros: Isso, quinta às dez. Eu reviso o site até quarta.")
        var b = Recording(title: L("Ideias para o grafo da memória"), locale: "pt-BR")
        b.date = now.addingTimeInterval(-26 * 3600); b.duration = 412; b.status = .ready
        b.summary = L("Anotações em voz sobre como ligar notas, capturas e gravações por assunto.")
        b.tasks = [Recording.Task(text: L("Testar o grafo com 200 itens"), owner: L("Eu"))]
        b.tags = [L("ideia"), L("memória")]
        var c = Recording(title: L("Call com o cliente: integração"), locale: "pt-BR")
        c.date = now.addingTimeInterval(-74 * 3600); c.duration = 2710; c.status = .ready
        c.summary = L("O cliente quer exportar os dados em CSV. Combinamos uma prova de conceito em duas semanas.")
        c.decisions = [L("Prova de conceito em duas semanas")]
        c.tasks = [Recording.Task(text: L("Enviar a proposta"), owner: L("Eu"), due: L("sexta"))]
        c.tags = [L("cliente"), L("integração")]; c.people = [L("Carla (cliente)")]
        items = [a, b, c]
        selectedID = a.id
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct MeetingNotes {
    @Guide(description: "Topics discussed in this part, in order, each with what was actually said")
    var topics: [NoteTopic]
    @Guide(description: "Decisions that were actually made, if any")
    var decisions: [String]
    @Guide(description: "What was planned next: meetings, presentations, follow-ups")
    var nextSteps: [String]
    @Guide(description: "Other relevant context: background, current state, risks, open questions")
    var remarks: [String]
    @Guide(description: "Names of people mentioned")
    var people: [String]
}

@available(macOS 26, *)
@Generable
struct MeetingTasks {
    @Guide(description: "Every action item in this part, each with its owner and deadline")
    var tasks: [MinuteTask]
}

@available(macOS 26, *)
@Generable
struct NoteTopic {
    @Guide(description: "Short title of the topic")
    var title: String
    @Guide(description: "Two to six specific points that were said about it")
    var points: [String]
}

@available(macOS 26, *)
@Generable
struct MeetingOverview {
    @Guide(description: "Short title for this meeting, under 60 characters")
    var title: String
    @Guide(description: "One or two sentences with the central subject of the meeting")
    var theme: String
    @Guide(description: "Three to five sentences with what matters, specific to what was discussed")
    var summary: String
    @Guide(description: "Two to five short topic tags")
    var tags: [String]
    @Guide(description: "Names of people mentioned")
    var people: [String]
}

@available(macOS 26, *)
@Generable
struct TaskCheck {
    @Guide(description: "true if someone asked for it, agreed to it, or said someone will do it")
    var askedOrPromised: Bool
}

@available(macOS 26, *)
@Generable
struct MinuteTask {
    @Guide(description: "The action, starting with a verb")
    var text: String
    @Guide(description: "Who will do it, or empty if unclear")
    var owner: String
    @Guide(description: "When it is due as said in the transcript, or empty")
    var due: String
}
#endif

/// Escreve buffers de áudio num .m4a, convertendo para mono 48 kHz
final class AudioFileWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var closed = false

    init(url: URL) throws {
        file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                                                           AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000],
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        let target = file.processingFormat
        if buffer.format == target { try? file.write(from: buffer); return }
        if converter == nil || converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: target) }
        guard let converter, let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64) else { return }
        var given = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return buffer
        }
        if err == nil, out.frameLength > 0 { try? file.write(from: out) }
    }

    func close() {
        lock.lock(); closed = true; lock.unlock()
    }
}

/// O som do Mac durante a gravação
final class RecordingSystemOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "menew.recording.system")
    var writer: AudioFileWriter?
    /// Sem microfone, o medidor de nível mostra o som do Mac
    var meter = false

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let w = writer, let pcm = CaptionAudioOutput.pcm(sampleBuffer) else { return }
        w.write(pcm)
        if meter {
            let peak = RecordingStore.peak(pcm)
            DispatchQueue.main.async { MainActor.assumeIsolated { RecordingStore.shared.level = peak } }
        }
    }
}

/// O modelo às vezes escreve "não especificado" em vez de deixar vazio
func meaningful(_ s: String) -> String? {
    let f = PaletteSearch.fold(s.trimmingCharacters(in: .whitespaces))
    let empty = ["nao especificado", "nao informado", "nao mencionado", "unspecified", "not specified", "not mentioned", "none", "n/a", "-",
                 "nenhum", "nicht angegeben", "keine", "no especificado", "ninguno", "未指定", "无",
                 "sem data", "sem prazo", "a definir", "indefinido", "no date", "no deadline", "tbd", "kein datum", "sin fecha", "无期限"]
    return f.isEmpty || empty.contains(f) ? nil : s
}

// MARK: Sobre mim

/// O que a IA precisa saber de você para escrever a ata do seu jeito: seu nome, como te chamam, quem são as pessoas
/// e o que significam as siglas e apelidos do seu trabalho. Fica só no Mac.
enum AboutMe {
    static let nameKey = "aboutMe.name"
    static let aliasesKey = "aboutMe.aliases"
    static let peopleKey = "aboutMe.people"
    static let glossaryKey = "aboutMe.glossary"

    static var name: String { UserDefaults.standard.string(forKey: nameKey) ?? NSFullUserName() }
    static var aliases: [String] {
        (UserDefaults.standard.string(forKey: aliasesKey) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Texto curto para as instruções da IA
    static func context() -> String {
        let d = UserDefaults.standard
        var parts = ["The user's name is \(name)."]
        if !aliases.isEmpty { parts.append("They are also called: \(aliases.joined(separator: ", ")).") }
        if let p = d.string(forKey: peopleKey), !p.isEmpty { parts.append("People they work with: \(p).") }
        if let g = d.string(forKey: glossaryKey), !g.isEmpty { parts.append("Glossary (term = meaning): \(g).") }
        parts.append("When a task belongs to the user, set the owner to \"\(L("Eu"))\".")
        return parts.joined(separator: " ")
    }

    static func isMe(_ owner: String?) -> Bool {
        guard let o = owner?.trimmingCharacters(in: .whitespaces), !o.isEmpty else { return true }
        let f = PaletteSearch.fold(o)
        return ([L("Eu"), "eu", "me", "i", name] + aliases).contains { PaletteSearch.fold($0) == f } || PaletteSearch.fold(name).hasPrefix(f)
    }
}
