import Foundation
import ServiceManagement

/// "Abrir ao iniciar o Mac": ligado por padrão para quem instala o Menew pela primeira vez
@MainActor
enum LaunchAtLogin {
    /// `true` enquanto falta ligar o padrão; `false` depois de ligado, para quem já usava o app ou se a pessoa mexeu no ajuste
    static let pendingKey = "launchAtLoginPending"

    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Chamado ao abrir o app. Só registra a cópia instalada em Aplicativos: abrir do .dmg (ou um build de
    /// desenvolvimento) não conta, e o padrão fica esperando o app ser aberto de lá.
    static func applyDefault(newUser: Bool) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: pendingKey) == nil { defaults.set(newUser, forKey: pendingKey) }
        guard defaults.bool(forKey: pendingKey), isInstalled else { return }
        defaults.set(false, forKey: pendingKey)
        if !isOn { try? SMAppService.mainApp.register() }
    }

    /// A pessoa ligou ou desligou no Ajustes: vale a escolha dela, o padrão não volta
    static func set(_ on: Bool) throws {
        UserDefaults.standard.set(false, forKey: pendingKey)
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    private static var isInstalled: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }
}
