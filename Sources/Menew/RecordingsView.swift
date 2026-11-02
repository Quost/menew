import AVFoundation
import SwiftUI

/// Janela Menew › Gravações: a lista por data à esquerda (com busca e etiquetas) e a ata à direita
struct RecordingsView: View {
    @ObservedObject var store = RecordingStore.shared
    @AppStorage(RecordingStore.sourceKey) private var sourceRaw = RecordingStore.Source.both.rawValue
    @AppStorage(RecordingStore.autoRemindersKey) private var autoReminders = false

    private var current: Recording? { store.items.first { $0.id == store.selectedID } ?? store.filtered.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                recordBar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Buscar nas gravações"), text: $store.query).textFieldStyle(.plain)
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                if !store.allTags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            chip(nil, L("Todas"))
                            ForEach(store.allTags.prefix(14), id: \.self) { chip($0, $0) }
                        }
                    }
                    .scrollIndicators(.never)
                }
                if store.items.isEmpty {
                    empty
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(groups, id: \.0) { day, list in
                                Text(day).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.top, 6)
                                ForEach(list) { r in row(r) }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .padding(16)
            .frame(width: 320)
            Divider()
            if let current {
                RecordingDetail(rec: current).id(current.id)
            } else {
                Text(L("Escolha uma gravação")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // Gravar: microfone, ou microfone e o som do Mac (para chamadas)
    private var recordBar: some View {
        HStack(spacing: 8) {
            Button { store.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.isRecording ? "stop.fill" : "record.circle")
                    if store.isRecording {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(RecordingStore.clock(ctx.date.timeIntervalSince(store.startedAt))).monospacedDigit()
                        }
                    } else {
                        Text(L("Gravar"))
                    }
                }
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.red.gradient))
            }
            .buttonStyle(.plain)
            .help(Shortcut.load(RecordingStore.shortcutKey, default: .recordingDefault).display)
            if store.isRecording {
                Capsule().fill(Color.red.opacity(0.25)).frame(width: 60 * CGFloat(min(1, store.level * 3)) + 4, height: 6)
                    .animation(.linear(duration: 0.1), value: store.level)
            } else {
                Picker("", selection: $sourceRaw) {
                    Text(L("Microfone")).tag(RecordingStore.Source.mic.rawValue)
                    Text(L("Microfone e som do Mac")).tag(RecordingStore.Source.both.rawValue)
                }
                .labelsHidden().fixedSize().controlSize(.small)
            }
            Spacer(minLength: 0)
            Menu {
                Toggle(L("Criar lembretes das minhas tarefas sozinho"), isOn: $autoReminders)
                Button(L("Sobre você (para a IA)…")) { SettingsWindow.shared.show(.ai) }
                Button(L("Mostrar a pasta no Finder")) { if let d = store.dir { NSWorkspace.shared.open(d) } }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }

    private var groups: [(String, [Recording])] {
        var out: [(String, [Recording])] = []
        for r in store.filtered {
            let day = Calendar.current.isDateInToday(r.date) ? L("Hoje") : Calendar.current.isDateInYesterday(r.date) ? L("Ontem")
                : r.date.formatted(.dateTime.weekday(.wide).day().month().locale(L10n.locale))
            if out.last?.0 == day { out[out.count - 1].1.append(r) } else { out.append((day, [r])) }
        }
        return out
    }

    private func row(_ r: Recording) -> some View {
        let on = r.id == current?.id
        return VStack(alignment: .leading, spacing: 3) {
            Text(r.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
            HStack(spacing: 6) {
                Text(r.date.formatted(date: .omitted, time: .shortened))
                if r.duration > 0 { Text(RecordingStore.clock(r.duration)) }
                switch r.status {
                case .recording: Label(L("gravando"), systemImage: "record.circle").foregroundStyle(.red)
                case .transcribing: Text(L("transcrevendo…"))
                case .summarizing: Text(L("escrevendo a ata…"))
                case .failed: Text(L("incompleta")).foregroundStyle(.orange)
                case .ready: if !r.tasks.isEmpty { Text(r.tasks.count == 1 ? L("1 tarefa") : L("%d tarefas", r.tasks.count)) }
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            if !r.tags.isEmpty {
                HStack(spacing: 4) { ForEach(r.tags.prefix(3), id: \.self) { MemoryTag($0) } }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(on ? Color.accentColor.opacity(0.15) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { store.selectedID = r.id }
        .contextMenu { Button(L("Apagar"), role: .destructive) { store.delete(r.id) } }
    }

    private func chip(_ value: String?, _ title: String) -> some View {
        Button { store.tag = value } label: {
            Text(title).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(store.tag == value ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.circle").font(.system(size: 34, weight: .light)).foregroundStyle(.red)
            Text(L("Grave reuniões, ideias e anotações em voz")).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
            Text(L("Aperte %@ para começar e parar. O Mac transcreve e a IA escreve a ata, com tarefas e etiquetas.",
                   Shortcut.load(RecordingStore.shortcutKey, default: .recordingDefault).display))
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RecordingDetail: View {
    let rec: Recording
    @ObservedObject var store = RecordingStore.shared
    @StateObject private var player = RecordingPlayer()
    @State private var showTranscript = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.title).font(.system(size: 18, weight: .bold)).textSelection(.enabled)
                    HStack(spacing: 8) {
                        Text(rec.date.formatted(date: .abbreviated, time: .shortened))
                        if rec.duration > 0 { Text("· " + RecordingStore.clock(rec.duration)) }
                        if !rec.people.isEmpty { Text("· " + rec.people.joined(separator: ", ")).lineLimit(1) }
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    if !rec.tags.isEmpty { FlowTags(tags: rec.tags).padding(.top, 2) }
                }
                if let url = store.audioURL(rec), FileManager.default.fileExists(atPath: url.path) {
                    HStack(spacing: 10) {
                        Button { player.toggle(url) } label: {
                            Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 28, height: 28)
                                .background(Circle().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        ProgressView(value: player.progress).progressViewStyle(.linear)
                    }
                }
                switch rec.status {
                case .transcribing, .summarizing:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(rec.status == .transcribing ? L("Transcrevendo no seu Mac…") : L("A IA está escrevendo a ata…")).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12.5))
                case .failed:
                    HStack {
                        Text(L("A gravação não terminou de ser processada.")).font(.system(size: 12.5)).foregroundStyle(.orange)
                        PillButton(title: L("Tentar de novo")) { Task { await store.process(rec.id) } }
                    }
                default: EmptyView()
                }
                if !rec.summary.isEmpty { section(L("Resumo")) { Text(rec.summary).font(.system(size: 13)).textSelection(.enabled) } }
                if !rec.decisions.isEmpty {
                    section(L("Decisões")) {
                        ForEach(rec.decisions, id: \.self) { d in
                            Label { Text(d).font(.system(size: 12.5)) } icon: { Image(systemName: "checkmark.seal").foregroundStyle(.green) }
                        }
                    }
                }
                if !rec.tasks.isEmpty {
                    section(L("Tarefas")) {
                        ForEach(rec.tasks) { t in
                            HStack(spacing: 8) {
                                Button {
                                    store.update(rec.id) { r in if let i = r.tasks.firstIndex(where: { $0.id == t.id }) { r.tasks[i].done.toggle() } }
                                } label: { Image(systemName: t.done ? "checkmark.circle.fill" : "circle").foregroundStyle(t.done ? .green : .secondary) }
                                    .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.text).font(.system(size: 12.5)).strikethrough(t.done)
                                    let meta = [t.owner, t.due].compactMap { $0 }.joined(separator: " · ")
                                    if !meta.isEmpty { Text(meta).font(.system(size: 11)).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 4)
                                if t.reminder {
                                    Label(L("No Lembretes"), systemImage: "checklist").font(.system(size: 11)).foregroundStyle(.secondary)
                                } else {
                                    Button(L("Lembrete")) { Task { await store.remind(rec.id, t.id) } }
                                        .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        if rec.tasks.contains(where: { !$0.reminder && AboutMe.isMe($0.owner) }) {
                            Button(L("Criar lembretes das minhas tarefas")) { Task { await store.remindMine(rec.id) } }
                                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor).padding(.top, 2)
                        }
                    }
                }
                if !rec.transcript.isEmpty {
                    DisclosureGroup(isExpanded: $showTranscript) {
                        Text(rec.transcript).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    } label: {
                        Text(L("Transcrição")).font(.system(size: 12, weight: .semibold))
                    }
                }
                HStack(spacing: 8) {
                    PillButton(title: L("Salvar como nota"), icon: "note.text") { store.saveAsNote(rec.id) }
                    PillButton(title: L("Copiar a ata"), icon: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(rec.markdown, forType: .string)
                        HUD.show(icon: "doc.on.doc.fill", color: .green, text: L("Copiado"))
                    }
                    Spacer()
                    IconButton(icon: "trash", help: L("Apagar")) { player.stop(); store.delete(rec.id) }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.never)
        .onDisappear { player.stop() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase)
            content()
        }
    }
}

/// Toca o áudio da gravação
@MainActor
final class RecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var progress = 0.0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ url: URL) {
        if playing { player?.pause(); playing = false; timer?.invalidate(); return }
        if player?.url != url { player = try? AVAudioPlayer(contentsOf: url); player?.delegate = self }
        player?.play()
        playing = player != nil
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let p = self.player, p.duration > 0 else { return }
                self.progress = p.currentTime / p.duration
            }
        }
    }

    func stop() { player?.stop(); playing = false; timer?.invalidate() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false; self.progress = 0; self.timer?.invalidate() }
    }
}

/// Ajustes › IA › Sobre você
struct AboutMeSection: View {
    @AppStorage(AboutMe.nameKey) private var name = NSFullUserName()
    @AppStorage(AboutMe.aliasesKey) private var aliases = ""
    @AppStorage(AboutMe.peopleKey) private var people = ""
    @AppStorage(AboutMe.glossaryKey) private var glossary = ""

    var body: some View {
        GlassSection(title: L("Sobre você"), footer: L("A IA usa isso nas atas das gravações: sabe quando uma tarefa é sua e entende os nomes e siglas do seu trabalho. Fica só no seu Mac.")) {
            field(L("Seu nome"), $name, "Ana Souza")
            RowDivider()
            field(L("Como te chamam"), $aliases, L("Ana, Aninha, AS"))
            RowDivider()
            field(L("Pessoas"), $people, L("Bruno: designer; Carla: cliente da Acme"))
            RowDivider()
            field(L("Glossário"), $glossary, L("PR = pull request; o Zé = José, gerente"))
        }
    }

    private func field(_ title: String, _ value: Binding<String>, _ hint: String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).frame(width: 130, alignment: .leading)
            TextField(hint, text: value).textFieldStyle(.roundedBorder).font(.system(size: 12.5))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
