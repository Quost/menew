import AppKit
import SwiftUI

/// Barra de menus profissional (como o iStat Menus): cada métrica escolhida ganha seu próprio ícone, e clicar nele
/// abre um painel só dela. O ícone do Menew continua abrindo o menu principal.
@MainActor
final class MenuBarPro: NSObject, NSPopoverDelegate {
    static let shared = MenuBarPro()
    static let key = "menuBarSeparate"

    private var items: [MenuBarItem: NSStatusItem] = [:]
    private var keys: [MenuBarItem: String] = [:]
    private let popover = NSPopover()
    private var openItem: MenuBarItem?
    private weak var monitor: SystemMonitor?
    var openMenew: () -> Void = {}

    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.key) }

    func attach(_ monitor: SystemMonitor) {
        self.monitor = monitor
        popover.behavior = .transient
        popover.delegate = self
    }

    /// Cria, tira ou atualiza os ícones (chamado a cada leitura do monitor)
    func update() {
        guard let monitor else { return }
        let wanted = isOn && !PresentationMode.shared.isOn ? MenuBarItem.selected : []
        for (item, status) in items where !wanted.contains(item) {
            NSStatusBar.system.removeStatusItem(status)
            items[item] = nil
            keys[item] = nil
        }
        // Os novos entram à esquerda: cria na ordem inversa para ficarem na ordem escolhida
        for item in wanted.reversed() where items[item] == nil {
            let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            s.autosaveName = "MenewMetric-\(item.rawValue)"
            s.button?.target = self
            s.button?.action = #selector(clicked(_:))
            s.button?.identifier = NSUserInterfaceItemIdentifier(item.rawValue)
            s.button?.setAccessibilityLabel(item.label)
            items[item] = s
        }
        if wanted.contains(.temp) { Sensors.shared.refresh() }
        for item in wanted {
            guard let button = items[item]?.button, let seg = item.segment(monitor) else { continue }
            guard keys[item] != seg.key || button.image == nil else { continue }
            keys[item] = seg.key
            button.image = StatusRenderer.image(segments: [seg], showIcon: false)
            button.imagePosition = .imageOnly
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let item = MenuBarItem(rawValue: raw), let monitor else { return }
        if popover.isShown {
            popover.performClose(nil)
            if openItem == item { return }
        }
        openItem = item
        monitor.isVisible = true
        monitor.wantsProcesses = item == .cpu || item == .cpuGraph
        if monitor.wantsProcesses { monitor.refreshProcesses() }
        let hosting = NSHostingController(rootView: MetricPanel(item: item, m: monitor) { [weak self] in
            self?.popover.performClose(nil)
            self?.openMenew()
        })
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidClose(_ notification: Notification) {
        openItem = nil
        monitor?.wantsProcesses = false
        // O menu principal pode estar aberto e também precisa das leituras completas
        if (NSApp.delegate as? AppDelegate)?.isMenuOpen != true { monitor?.isVisible = false }
    }
}

/// Painel de uma métrica, aberto pelo ícone dela na barra
struct MetricPanel: View {
    let item: MenuBarItem
    @ObservedObject var m: SystemMonitor
    var openMenew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
            HStack {
                Spacer()
                Button(L("Abrir o Menew"), action: openMenew)
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.accentColor)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(Theme.windowFill)
    }

    @ViewBuilder private var content: some View {
        switch item {
        case .cpu, .cpuGraph:
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: L("Processador"), icon: "cpu", color: Theme.cpu)
                HStack(alignment: .bottom, spacing: 12) {
                    Text(Fmt.pct(m.cpu)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Sparkline(values: m.cpuHistory, color: Theme.load(m.cpu, base: Theme.cpu)).frame(height: 40)
                }
                if let g = m.gpu {
                    HStack(spacing: 12) {
                        Text("GPU " + Fmt.pct(g)).font(.system(size: 12, weight: .semibold)).frame(width: 72, alignment: .leading)
                        Sparkline(values: m.gpuHistory, color: .pink).frame(height: 20)
                    }
                }
                if !m.coreLoads.isEmpty { CoreBars(loads: m.coreLoads) }
                ForEach(m.topProcesses.prefix(5)) { p in
                    ProcessRow(p: p) { force in if !m.quit(p, force: force) { NSSound.beep() } }
                }
            }
            .card()
        case .ram:
            MemoryCard(m: m)
        case .net:
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: L("Rede"), icon: "network", color: Theme.download)
                HStack(spacing: 10) {
                    NetStat(title: L("Download"), icon: "arrow.down", color: Theme.download, value: m.netIn, history: m.netInHistory)
                    NetStat(title: L("Upload"), icon: "arrow.up", color: Theme.upload, value: m.netOut, history: m.netOutHistory)
                }
                if m.isDemo { WiFiDetails(w: .demo) } else { WiFiRow() }
                NetAppsSection()
            }
            .card()
        case .disk:
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: L("Disco"), icon: "internaldrive", color: Theme.disk) {
                    Text(L("%@ livres", Fmt.bytes(m.diskFree))).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    NetStat(title: L("Leitura"), icon: "arrow.down.doc", color: Theme.disk, value: m.diskRead, history: m.diskReadHistory)
                    NetStat(title: L("Gravação"), icon: "square.and.arrow.down", color: .orange, value: m.diskWrite, history: m.diskWriteHistory)
                }
                DiskHealthRow()
            }
            .card()
        case .battery:
            VStack(spacing: 10) {
                if let b = m.battery, let h = m.batteryHealth { BatteryCard(battery: b, health: h) }
                AccessoriesCard()
            }
        case .temp:
            SensorsCard()
        }
    }
}
