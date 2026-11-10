import AppKit
import UserNotifications

/// Avisos do macOS quando algo precisa de atenção. Todos começam desligados (Ajustes → Alertas)
/// e cada um avisa uma vez, até a situação se resolver.
@MainActor
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alerts()

    enum Kind: String, CaseIterable {
        case disk = "alertDisk", battery = "alertBattery", memory = "alertMemory", cpu = "alertCPU", thermal = "alertThermal"
        case charged = "alertCharged", batteryHot = "alertBatteryHot"

        var title: String {
            switch self {
            case .disk: L("Disco quase cheio")
            case .battery: L("Bateria baixa")
            case .memory: L("Memória no limite")
            case .cpu: L("CPU alta por muito tempo")
            case .thermal: L("Mac esquentando")
            case .charged: L("Bateria carregada")
            case .batteryHot: L("Bateria quente")
            }
        }
        var icon: String {
            switch self {
            case .disk: "internaldrive"
            case .battery: "battery.25percent"
            case .memory: "memorychip"
            case .cpu: "flame"
            case .thermal: "thermometer.high"
            case .charged: "battery.100percent.bolt"
            case .batteryHot: "thermometer.sun"
            }
        }
        var enabled: Bool { UserDefaults.standard.bool(forKey: rawValue) }
    }

    private var fired: Set<Kind> = []

    /// Nível do aviso "Bateria carregada" (80, 85, 90 ou 95%)
    static let chargedLevelKey = "alertChargedLevel"
    static var chargedLevel: Int {
        let v = UserDefaults.standard.integer(forKey: chargedLevelKey)
        return [80, 85, 90, 95].contains(v) ? v : 80
    }
    private var memoryStreak = 0
    private var cpuStreak = 0
    private var center: UNUserNotificationCenter? {
        // Sem bundle (binário solto, testes) o UNUserNotificationCenter derruba o app
        Bundle.main.bundleIdentifier == nil || Bundle.main.bundleURL.pathExtension != "app" ? nil : .current()
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
        // Cuidados com a bateria: avisa ao chegar no nível escolhido na tomada e quando ela esquenta
        BatteryLog.shared.update(m.batteryHealth)
        BatteryWear.shared.record(m.battery, m.batteryHealth)
        if let b = m.battery {
            let level = Self.chargedLevel
            evaluate(.charged, on: b.onAC && b.percent >= level && level < 100, off: !b.onAC || b.percent < level - 5) {
                L("Chegou a %d%%. Para a bateria durar mais, tire da tomada quando puder.", b.percent)
            }
        }
        if let t = m.batteryHealth?.temperature {
            evaluate(.batteryHot, on: t >= 40, off: t < 36) {
                L("A bateria está a %d °C. Calor é o que mais desgasta: deixe as saídas de ar livres e evite carregar no sol.", Int(t))
            }
        }
        // Memória: pressão crítica por ~10 s seguidos
        memoryStreak = m.memPressure == .critical ? memoryStreak + 1 : 0
        evaluate(.memory, on: memoryStreak >= 5, off: m.memPressure == .normal) {
            L("O Mac está sem memória livre e pode ficar lento. Feche apps que não está usando.")
        }
        // Temperatura: o próprio macOS diz que está quente (ele já reduz a velocidade nesse ponto)
        evaluate(.thermal, on: m.thermal == .serious || m.thermal == .critical, off: m.thermal == .nominal) {
            L("O Mac está quente e pode ficar mais lento. Feche apps pesados ou deixe as saídas de ar livres.")
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

    /// Aviso avulso (bateria de acessório, por exemplo); só aparece se as notificações estiverem permitidas
    func notify(id: String, title: String, body: String, userInfo: [String: String] = [:]) {
        guard let center else { return }
        center.delegate = self
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
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

    // Clicar no aviso de reunião abre o link da chamada
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        // O aviso de um agente de IA traz o terminal dele para a frente
        if let id = response.notification.request.content.userInfo["agentSession"] as? String {
            DispatchQueue.main.async { MainActor.assumeIsolated { AgentHub.shared.focus(id: id) } }
        }
        completionHandler()
    }

    // Mostra o aviso mesmo com o popover do Menew aberto
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
