import SwiftUI
import UserNotifications
import IOKit.ps

// MARK: Memória

struct MemoryCard: View {
    @ObservedObject var m: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: L("Memória"), icon: "memorychip", color: Theme.memory) {
                PressureBadge(pressure: m.memPressure)
            }
            SegmentedBar(parts: parts.map { (Double($0.bytes), $0.color) }, total: Double(m.memTotal))
                .frame(height: 8)
            HStack(spacing: 0) {
                ForEach(parts, id: \.title) { p in
                    LegendValue(color: p.color, title: p.title, value: Fmt.memShort(p.bytes))
                }
                LegendValue(color: .secondary.opacity(0.5), title: "Swap", value: Fmt.memShort(m.swapUsed))
            }
        }
        .card()
        .help(L("A pressão de memória mostra se o Mac precisa de mais memória. Se estiver normal, está tudo bem, mesmo com a memória quase toda usada."))
    }

    private var parts: [(title: String, bytes: UInt64, color: Color)] {
        [(L("Apps"), m.memBreakdown.app, Theme.memory),
         (L("Sistema"), m.memBreakdown.wired, .orange),
         (L("Comprimida"), m.memBreakdown.compressed, .yellow)]
    }
}

struct PressureBadge: View {
    let pressure: MemoryPressure

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .foregroundStyle(color)
    }

    private var text: String {
        switch pressure {
        case .normal: L("Pressão normal")
        case .warning: L("Pressão alta")
        case .critical: L("Pressão crítica")
        }
    }

    private var color: Color {
        switch pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct SegmentedBar: View {
    let parts: [(Double, Color)]
    let total: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    Rectangle().fill(p.1).frame(width: max(0, geo.size.width * p.0 / max(total, 1) - 1.5))
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.07))
            .clipShape(Capsule())
        }
    }
}

struct LegendValue: View {
    let color: Color, title: String, value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Bateria

struct BatteryCard: View {
    let battery: BatteryInfo
    let health: BatteryHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: L("Bateria"), icon: battery.charging ? "battery.100percent.bolt" : "battery.75percent",
                       color: Theme.battery) {
                if let h = health.healthPercent, h < 80 {
                    Text(L("Assistência recomendada")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 0) {
                if let h = health.healthPercent {
                    BatteryValue(title: L("Saúde"), value: "\(h)%", color: h < 80 ? .orange : Theme.battery)
                }
                if let c = health.cycles {
                    BatteryValue(title: L("Ciclos"), value: "\(c)", color: .primary)
                }
                BatteryValue(title: L("Carregador"), value: health.adapterWatts.map { "\($0) W" } ?? "—", color: .primary)
                if let t = health.temperature {
                    BatteryValue(title: L("Temperatura"), value: String(format: "%.0f °C", t), color: .primary)
                }
            }
        }
        .card()
    }
}

private struct BatteryValue: View {
    let title: String, value: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Processos

struct ProcessRow: View {
    let p: ProcInfo
    let onQuit: (Bool) -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = AppIcons.icon(forProcess: p.name) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "gearshape.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            Text(p.name).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 6)
            Text(Fmt.mem(p.memKB * 1024)).font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
            UsageBar(fraction: min(p.cpu / 100, 1), color: Theme.cpu, height: 4).frame(width: 44)
            ZStack(alignment: .trailing) {
                Text(String(format: "%.0f%%", p.cpu)).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                    .opacity(hover ? 0 : 1)
                if hover {
                    Button { onQuit(false) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Encerrar %@", p.name))
                }
            }
            .frame(width: 36, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 && p.pid > 1 }
        .contextMenu {
            Button(L("Encerrar")) { onQuit(false) }
            Button(L("Forçar encerramento")) { onQuit(true) }
        }
    }
}

// MARK: Ajustes

/// Fichas para escolher o que aparece na barra, com uma prévia ao vivo
struct MenuBarItemsPicker: View {
    @Binding var selection: String
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Mostrar ao lado do ícone"))
                Spacer()
                let segs = MenuBarItem.allCases.filter { chosen.contains($0) }.map(\.sample)
                Image(nsImage: StatusRenderer.image(segments: segs))
                    .renderingMode(.template)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
            }
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(MenuBarItem.allCases, id: \.self) { item in
                    let on = chosen.contains(item)
                    Button { toggle(item) } label: {
                        Label(item.label, systemImage: item.icon)
                            .font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(on ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.06))))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var chosen: Set<MenuBarItem> {
        Set(selection.split(separator: ",").compactMap { MenuBarItem(rawValue: String($0)) })
    }

    private func toggle(_ item: MenuBarItem) {
        var set = chosen
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
        selection = MenuBarItem.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}

struct AlertsSection: View {
    @AppStorage(Alerts.Kind.disk.rawValue) private var disk = false
    @AppStorage(Alerts.Kind.battery.rawValue) private var battery = false
    @AppStorage(Alerts.Kind.memory.rawValue) private var memory = false
    @AppStorage(Alerts.Kind.cpu.rawValue) private var cpu = false
    @State private var denied = false

    var body: some View {
        Section(L("Alertas")) {
            toggle(.disk, $disk, L("Menos de 10 GB livres"))
            if SystemMonitorInfo.hasBattery { toggle(.battery, $battery, L("20% ou menos, fora da tomada")) }
            toggle(.memory, $memory, L("Pressão de memória crítica"))
            toggle(.cpu, $cpu, L("Acima de 90% por 2 minutos"))
            if denied {
                HStack {
                    Text(L("As notificações do Menew estão desligadas no macOS.")).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button(L("Abrir Ajustes")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            } else {
                Text(L("Um aviso do macOS quando algo precisa da sua atenção. Cada alerta avisa uma vez, até a situação se resolver."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refreshDenied)
    }

    private func toggle(_ kind: Alerts.Kind, _ value: Binding<Bool>, _ detail: String) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 1) {
                Label(kind.title, systemImage: kind.icon)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: value.wrappedValue) { _, on in
            if on { Alerts.shared.requestPermission { granted in denied = !granted } }
        }
    }

    private func refreshDenied() {
        guard Bundle.main.bundleIdentifier != nil, [disk, battery, memory, cpu].contains(true) else { return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let off = s.authorizationStatus == .denied
            Task { @MainActor in denied = off }
        }
    }
}

enum SystemMonitorInfo {
    static let hasBattery: Bool = {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return !list.isEmpty
    }()
}
