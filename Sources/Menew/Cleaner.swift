import AppKit
import SwiftUI

// MARK: Modelo

struct CleanItem: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    var selected: Bool
}

struct CleanCategory: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
    /// Arquivos do usuário: vêm desmarcados, são revisados item a item e vão para a Lixeira.
    /// Os demais (caches, logs) são apagados, porque os apps os recriam.
    let review: Bool
    var items: [CleanItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var allSelected: Bool { !items.isEmpty && items.allSatisfy(\.selected) }
}

/// Dados crus da varredura (sem cores/textos), montados fora da thread principal
private struct ScanResult: Sendable {
    let id: String
    let review: Bool
    let items: [(URL, Int64)]
}

@MainActor
final class Cleaner: ObservableObject {
    enum Phase: Equatable { case idle, scanning, ready, cleaning, done(Int64) }

    @Published var phase: Phase = .idle
    @Published var categories: [CleanCategory] = []
    @Published var deep = false
    @Published var memoryHogs: [(app: NSRunningApplication, mb: Int)] = []

    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }

    func scan(deep: Bool) {
        self.deep = deep
        phase = .scanning
        Task {
            let results = await Task.detached { Cleaner.scanAll(deep: deep) }.value
            categories = results.compactMap(makeCategory).filter { $0.totalSize > 0 }
            phase = .ready
        }
    }

    func toggle(category id: String) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        let value = !categories[i].allSelected
        for j in categories[i].items.indices { categories[i].items[j].selected = value }
    }

    func toggle(item: UUID, in id: String) {
        guard let i = categories.firstIndex(where: { $0.id == id }),
              let j = categories[i].items.firstIndex(where: { $0.id == item }) else { return }
        categories[i].items[j].selected.toggle()
    }

    func clean() {
        let jobs = categories.flatMap { c in c.items.filter(\.selected).map { ($0.url, $0.size, c.review) } }
        phase = .cleaning
        Task {
            let freed = await Task.detached { () -> Int64 in
                var freed: Int64 = 0
                for (url, size, review) in jobs {
                    do {
                        if review {
                            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        } else {
                            try FileManager.default.removeItem(at: url)
                        }
                        freed += size
                    } catch {
                        // Em uso ou protegido pelo sistema: segue para o próximo
                    }
                }
                return freed
            }.value
            phase = .done(freed)
        }
    }

    func reset() {
        phase = .idle
        categories = []
    }

    // MARK: Memória

    /// Apps abertos que mais usam memória (para encerrar, em vez de "limpar RAM", que não existe de verdade)
    func refreshMemory() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let pids = apps.map { String($0.processIdentifier) }.joined(separator: ",")
        guard !pids.isEmpty else { memoryHogs = []; return }
        Task {
            let out = await Task.detached { Shell.run("/bin/ps", ["-o", "pid=,rss=", "-p", pids]) }.value
            var rss: [pid_t: Int] = [:]
            for line in out.split(separator: "\n") {
                let p = line.split(separator: " ", omittingEmptySubsequences: true)
                if p.count == 2, let pid = pid_t(p[0]), let kb = Int(p[1]) { rss[pid] = kb / 1024 }
            }
            memoryHogs = apps.compactMap { app in rss[app.processIdentifier].map { (app: app, mb: $0) } }
                .sorted { $0.mb > $1.mb }
                .prefix(5).map { $0 }
        }
    }

    // MARK: Categorias

    private func makeCategory(_ r: ScanResult) -> CleanCategory? {
        let items = r.items.map { CleanItem(url: $0.0, size: $0.1, selected: !r.review) }
        func cat(_ title: String, _ detail: String, _ icon: String, _ color: Color) -> CleanCategory {
            CleanCategory(id: r.id, title: title, detail: detail, icon: icon, color: color, review: r.review, items: items)
        }
        switch r.id {
        case "caches": return cat(L("Caches de apps"), L("Os apps recriam quando precisam"), "archivebox.fill", .blue)
        case "logs": return cat(L("Logs"), L("Registros antigos de apps e do sistema"), "doc.text.fill", .gray)
        case "derived": return cat(L("Xcode: DerivedData"), L("Arquivos de compilação, recriados no próximo build"), "hammer.fill", .indigo)
        case "simcaches": return cat(L("Simuladores: caches"), L("Caches dos simuladores do iOS"), "iphone", .teal)
        case "devcaches": return cat(L("Caches de desenvolvimento"), L("npm, Gradle e afins"), "shippingbox.fill", .orange)
        case "devicesupport": return cat(L("Xcode: suporte a dispositivos"), L("Baixado de novo ao conectar o aparelho"), "cable.connector", .purple)
        case "archives": return cat(L("Xcode: Archives"), L("Builds antigos exportados; revise antes"), "archivebox", .pink)
        case "downloads": return cat(L("Downloads antigos"), L("Mais de 90 dias; revise antes"), "arrow.down.circle.fill", .green)
        case "large": return cat(L("Arquivos grandes"), L("Mais de 500 MB; revise antes"), "externaldrive.fill", .red)
        default: return nil
        }
    }

    // MARK: Varredura (fora da thread principal)

    nonisolated private static func scanAll(deep: Bool) -> [ScanResult] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let lib = home.appendingPathComponent("Library")
        var out: [ScanResult] = [
            // Caches do próprio macOS ficam de fora: alguns fazem o sistema ressincronizar dados
            ScanResult(id: "caches", review: false, items: children(lib.appendingPathComponent("Caches"))
                .filter { !$0.0.lastPathComponent.hasPrefix("com.apple.") }),
            ScanResult(id: "logs", review: false, items: children(lib.appendingPathComponent("Logs"))),
            ScanResult(id: "derived", review: false, items: children(lib.appendingPathComponent("Developer/Xcode/DerivedData"))),
            ScanResult(id: "simcaches", review: false, items: children(lib.appendingPathComponent("Developer/CoreSimulator/Caches"))),
            ScanResult(id: "devcaches", review: false, items: [
                home.appendingPathComponent(".npm/_cacache"),
                home.appendingPathComponent(".gradle/caches"),
            ].compactMap { u in let s = size(of: u); return s > 0 ? (u, s) : nil }),
        ]
        guard deep else { return out }
        out += [
            ScanResult(id: "devicesupport", review: false, items: children(lib.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"))),
            ScanResult(id: "archives", review: true, items: children(lib.appendingPathComponent("Developer/Xcode/Archives"))),
            ScanResult(id: "downloads", review: true, items: oldDownloads(home.appendingPathComponent("Downloads"))),
            ScanResult(id: "large", review: true, items: largeFiles(in: home)),
        ]
        return out
    }

    /// Cada item dentro da pasta, com o tamanho (a pasta em si fica)
    nonisolated private static func children(_ dir: URL) -> [(URL, Int64)] {
        let list = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return list.compactMap { u in
            let s = size(of: u)
            return s > 0 ? (u, s) : nil
        }
        .sorted { $0.1 > $1.1 }
    }

    nonisolated private static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey, .isDirectoryKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        if v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? 0) }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [],
                                                     errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let r = try? f.resourceValues(forKeys: keys), r.isRegularFile == true {
                total += Int64(r.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    nonisolated private static func oldDownloads(_ dir: URL) -> [(URL, Int64)] {
        let cutoff = Date().addingTimeInterval(-90 * 86_400)
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]
        let list = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return list.compactMap { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            guard let d = v?.addedToDirectoryDate ?? v?.creationDate, d < cutoff else { return nil }
            let s = size(of: u)
            return s > 0 ? (u, s) : nil
        }
        .sorted { $0.1 > $1.1 }
    }

    /// Arquivos acima de 500 MB na pasta pessoal, fora da Biblioteca e de pastas ocultas
    nonisolated private static func largeFiles(in home: URL) -> [(URL, Int64)] {
        let limit: Int64 = 500 * 1_048_576
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let e = FileManager.default.enumerator(at: home, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                     errorHandler: { _, _ in true }) else { return [] }
        let skip = Set(["Library", "Applications"].map { home.appendingPathComponent($0).path })
        var found: [(URL, Int64)] = []
        for case let f as URL in e {
            if skip.contains(f.path) { e.skipDescendants(); continue }
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let s = Int64(v.totalFileAllocatedSize ?? 0)
            if s >= limit { found.append((f, s)) }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(50).map { $0 }
    }
}

// MARK: Tela

struct CleanerView: View {
    @ObservedObject var cleaner: Cleaner
    @ObservedObject var monitor: SystemMonitor
    @State private var expanded: Set<String> = []
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            switch cleaner.phase {
            case .idle: start
            case .scanning: progress(L("Analisando o disco…"))
            case .cleaning: progress(L("Limpando…"))
            case .ready: results
            case .done(let freed): done(freed)
            }
        }
        .onAppear { cleaner.refreshMemory() }
    }

    // Início: espaço em disco, os dois modos e memória
    private var start: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(title: L("Disco"), icon: "internaldrive", color: Theme.disk) {
                        Text(L("%@ livres", Fmt.bytes(monitor.diskFree))).font(.system(size: 12, weight: .semibold))
                    }
                    UsageBar(fraction: monitor.diskFraction, color: Theme.load(monitor.diskFraction, base: Theme.disk), height: 8)
                }
                .card()

                ModeButton(icon: "sparkles", color: .blue, title: L("Análise rápida"),
                           detail: L("Caches, logs e arquivos de desenvolvimento. Seguro: os apps recriam o que precisarem.")) {
                    cleaner.scan(deep: false)
                }
                ModeButton(icon: "magnifyingglass.circle.fill", color: .purple, title: L("Análise profunda"),
                           detail: L("Também procura downloads antigos, arquivos grandes e itens do Xcode. Você revisa, e o que for removido vai para a Lixeira.")) {
                    cleaner.scan(deep: true)
                }

                if !cleaner.memoryHogs.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        CardHeader(title: L("Apps usando mais memória"), icon: "memorychip", color: Theme.memory)
                        ForEach(cleaner.memoryHogs, id: \.app.processIdentifier) { hog in
                            HStack(spacing: 8) {
                                if let icon = hog.app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                                Text(hog.app.localizedName ?? "?").font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                Text(Fmt.mem(UInt64(hog.mb) * 1_048_576)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                                Button(L("Encerrar")) {
                                    hog.app.terminate()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { cleaner.refreshMemory() }
                                }
                                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.indigo)
                            }
                        }
                        Text(L("O macOS já gerencia a memória sozinho. Encerrar um app pesado é o que realmente libera espaço."))
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                    .card()
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .scrollIndicators(.never)
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        VStack(spacing: 0) {
            if cleaner.categories.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(.green)
                    Text(L("Nada para limpar. Tudo em ordem!")).font(.system(size: 13)).foregroundStyle(.secondary)
                    PillButton(title: L("Voltar")) { cleaner.reset() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(cleaner.categories) { c in categoryCard(c) }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
                .scrollIndicators(.never)

                Divider()
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Selecionado")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        Text(Fmt.bytes(cleaner.selectedSize)).font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    PillButton(title: L("Cancelar")) { cleaner.reset() }
                    PillButton(title: L("Limpar"), icon: "trash", primary: true) { confirm = true }
                        .disabled(cleaner.selectedSize == 0)
                        .opacity(cleaner.selectedSize == 0 ? 0.5 : 1)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .confirmationDialog(L("Liberar %@?", Fmt.bytes(cleaner.selectedSize)), isPresented: $confirm) {
                    Button(L("Limpar"), role: .destructive) { cleaner.clean() }
                } message: {
                    Text(L("Caches e logs são apagados (os apps recriam). Arquivos seus vão para a Lixeira."))
                }
            }
        }
    }

    private func categoryCard(_ c: CleanCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(get: { c.allSelected }, set: { _ in cleaner.toggle(category: c.id) }))
                    .toggleStyle(.checkbox).labelsHidden()
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(c.color.gradient)
                    Image(systemName: c.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.title).font(.system(size: 12.5, weight: .medium))
                    Text(c.detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Fmt.bytes(c.review ? c.selectedSize : c.totalSize))
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Button {
                    if expanded.contains(c.id) { expanded.remove(c.id) } else { expanded.insert(c.id) }
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(expanded.contains(c.id) ? 90 : 0))
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if expanded.contains(c.id) {
                VStack(spacing: 4) {
                    ForEach(c.items.prefix(30)) { item in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(get: { item.selected }, set: { _ in cleaner.toggle(item: item.id, in: c.id) }))
                                .toggleStyle(.checkbox).labelsHidden().controlSize(.small)
                            Text(item.url.lastPathComponent).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.bytes(item.size)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                                Image(systemName: "magnifyingglass").font(.system(size: 10))
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Mostrar no Finder"))
                        }
                    }
                    if c.items.count > 30 {
                        Text(L("e mais %d", c.items.count - 30)).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 30)
            }
        }
        .card(padding: 10)
    }

    private func done(_ freed: Int64) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.gradient).frame(width: 72, height: 72)
                Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            }
            .shadow(color: .green.opacity(0.35), radius: 12, y: 4)
            Text(L("%@ liberados", Fmt.bytes(freed))).font(.system(size: 20, weight: .bold, design: .rounded))
            Text(L("Alguns itens em uso podem ter ficado para trás.")).font(.system(size: 11.5)).foregroundStyle(.secondary)
            PillButton(title: L("Concluir"), primary: true) { cleaner.reset() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModeButton: View {
    let icon: String, color: Color, title: String, detail: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.gradient)
                    Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(hover ? 0.05 : 0))))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
