import AppKit
import UserNotifications

/// Avisos do macOS quando algo precisa de atenção. Todos começam desligados (Ajustes → Alertas)
/// e cada um avisa uma vez, até a situação se resolver.
@MainActor
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alerts()

    enum Kind: String, CaseIterable {
        case disk = "alertDisk", battery = "alertBattery", memory = "alertMemory", cpu = "alertCPU"

        var title: String {
            switch self {
            case .disk: L("Disco quase cheio")
            case .battery: L("Bateria baixa")
            case .memory: L("Memória no limite")
            case .cpu: L("CPU alta por muito tempo")
            }
        }
        var icon: String {
            switch self {
            case .disk: "internaldrive"
            case .battery: "battery.25percent"
            case .memory: "memorychip"
            case .cpu: "flame"
            }
        }
        var enabled: Bool { UserDefaults.standard.bool(forKey: rawValue) }
    }

    private var fired: Set<Kind> = []
    private var memoryStreak = 0
    private var cpuStreak = 0
    private var center: UNUserNotificationCenter? {
        // Sem bundle (binário solto, testes) o UNUserNotificationCenter derruba o app
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        guard let center else { return done(false) }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    func check(_ m: SystemMonitor) {
        // Disco: menos de 5% ou 10 GB livres; volta a avisar depois de passar de 8% / 15 GB
        if m.diskTotal > 0 {
            let free = Double(m.diskFree), total = Double(m.diskTotal)
            evaluate(.disk, on: free < total * 0.05 || free < 10e9, off: free > total * 0.08 && free > 15e9) {
                L("Restam só %@. Que tal liberar espaço no Menew?", Fmt.bytes(m.diskFree))
            }
        }
        if let b = m.battery {
            evaluate(.battery, on: !b.onAC && b.percent <= 20, off: b.onAC) {
                L("Restam %d%%. Conecte o carregador.", b.percent)
            }
        }
        // Memória: pressão crítica por ~10 s seguidos
        memoryStreak = m.memPressure == .critical ? memoryStreak + 1 : 0
        evaluate(.memory, on: memoryStreak >= 5, off: m.memPressure == .normal) {
            L("O Mac está sem memória livre e pode ficar lento. Feche apps que não está usando.")
        }
        // CPU: acima de 90% por 2 minutos (60 leituras de 2 s)
        cpuStreak = m.cpu > 0.9 ? cpuStreak + 1 : 0
        if Kind.cpu.enabled, cpuStreak >= 60, !fired.contains(.cpu) {
            fired.insert(.cpu)
            Task.detached {
                let top = SystemMonitor.readTopProcesses().first
                await MainActor.run {
                    let body = top.map { L("%@ está usando %d%% da CPU há 2 minutos.", $0.name, Int($0.cpu)) }
                        ?? L("A CPU está acima de 90% há 2 minutos.")
                    self.post(.cpu, body: body)
                }
            }
        } else if m.cpu < 0.5 {
            fired.remove(.cpu)
        }
    }

    private func evaluate(_ kind: Kind, on: Bool, off: Bool, body: () -> String) {
        if on, kind.enabled, !fired.contains(kind) {
            fired.insert(kind)
            post(kind, body: body())
        } else if off {
            fired.remove(kind)
        }
    }

    private func post(_ kind: Kind, body: String) {
        guard let center else { return }
        center.delegate = self
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: kind.rawValue, content: content, trigger: nil))
    }

    // Mostra o aviso mesmo com o popover do Menew aberto
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
