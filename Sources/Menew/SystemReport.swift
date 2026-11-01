import AppKit
import SwiftUI

/// Saúde do disco interno (SMART), lida do `diskutil` uma vez por abertura do Menew
@MainActor
final class DiskHealth: ObservableObject {
    static let shared = DiskHealth()
    @Published private(set) var status: String?
    @Published private(set) var model: String?
    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        Task {
            let out = await Task.detached { Shell.run("/usr/sbin/diskutil", ["info", "disk0"]) }.value
            for line in out.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                if parts[0] == "SMART Status" { status = parts[1] }
                if parts[0] == "Device / Media Name" { model = parts[1] }
            }
        }
    }

    /// "Verified" → "Verificado"; "Failing" → aviso
    var label: String? {
        guard let status else { return nil }
        switch status.lowercased() {
        case "verified": return L("Saudável")
        case "failing": return L("Falhando: faça backup agora")
        case "not supported": return nil
        default: return status
        }
    }

    var ok: Bool { status?.lowercased() != "failing" }
}

/// "Copiar relatório do sistema": texto pronto para mandar ao suporte ou à TI
@MainActor
enum SystemReport {
    static func text(_ m: SystemMonitor) -> String {
        func sysctl(_ name: String) -> String {
            var size = 0
            sysctlbyname(name, nil, &size, nil, 0)
            var buf = [CChar](repeating: 0, count: max(size, 1))
            sysctlbyname(name, &buf, &size, nil, 0)
            return String(cString: buf)
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var lines = [
            "Mac: \(sysctl("hw.model")) · \(sysctl("machdep.cpu.brand_string"))",
            "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            L("Memória: %@ (em uso %@, pressão %@)", Fmt.mem(m.memTotal), Fmt.mem(m.memUsed),
              m.memPressure == .normal ? L("normal") : m.memPressure == .warning ? L("alta") : L("crítica")),
            L("Disco: %@ livres de %@", Fmt.bytes(m.diskFree), Fmt.bytes(m.diskTotal)),
            L("CPU agora: %d%%", Int(m.cpu * 100)),
            L("Ligado há: %@", Fmt.duration(m.uptime)),
        ]
        if let label = DiskHealth.shared.label { lines.append(L("Saúde do SSD: %@", label)) }
        if let b = m.battery {
            var bat = L("Bateria: %d%%", b.percent)
            if let h = m.batteryHealth?.healthPercent { bat += " · " + L("saúde %d%%", h) }
            if let c = m.batteryHealth?.cycles { bat += " · " + L("%d ciclos", c) }
            lines.append(bat)
        }
        lines.append("Menew \(version)")
        return lines.joined(separator: "\n")
    }

    static func copy(_ m: SystemMonitor) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text(m), forType: .string)
        HUD.show(icon: "doc.on.clipboard.fill", color: .green, text: L("Relatório copiado"))
    }
}

/// Linha da saúde do SSD no cartão Disco
struct DiskHealthRow: View {
    @ObservedObject var health = DiskHealth.shared

    var body: some View {
        // VStack (não Group): um Group vazio não recebe onAppear, e a leitura nunca começava
        VStack(spacing: 0) {
            if let label = health.label {
                HStack(spacing: 6) {
                    Image(systemName: health.ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(health.ok ? .green : .red)
                    Text(L("Saúde do SSD: %@", label)).font(.system(size: 11.5, weight: .medium))
                    Spacer(minLength: 4)
                    if let model = health.model { Text(model).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1) }
                }
                .font(.system(size: 11))
            }
        }
        .onAppear { health.load() }
    }
}
