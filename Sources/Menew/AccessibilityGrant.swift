import AppKit
import ApplicationServices
import Security

/// Permissão de Acessibilidade (usada para mandar ⌘V ao colar).
///
/// O macOS guarda a permissão presa à assinatura do app. Num build assinado ad-hoc (sem certificado) a
/// assinatura é o hash do binário, então cada build novo deixa o Menew ligado na lista de Ajustes sem valer
/// mais nada. Pedir de novo pelo diálogo do sistema não resolve: é preciso remover e adicionar o Menew.
@MainActor
enum AccessibilityGrant {
    private static let grantedKey = "accessibilityGrantedOnce"
    private static var promptedThisLaunch = false

    /// Se pode mandar teclas agora. Lembra que já funcionou uma vez, para reconhecer uma permissão vencida depois.
    static var isTrusted: Bool {
        let trusted = AXIsProcessTrusted()
        if trusted { UserDefaults.standard.set(true, forKey: grantedKey) }
        return trusted
    }

    /// Chamado quando falta a permissão: na primeira vez, o diálogo do sistema; se o Menew já tinha a
    /// permissão antes (ou o diálogo já apareceu nesta sessão), explica que a da lista é de outra cópia.
    static func request() {
        guard !AXIsProcessTrusted() else { return }
        if shouldExplainStale(grantedBefore: UserDefaults.standard.bool(forKey: grantedKey), promptedThisLaunch: promptedThisLaunch) {
            showStaleHint()
            return
        }
        promptedThisLaunch = true
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    nonisolated static func shouldExplainStale(grantedBefore: Bool, promptedThisLaunch: Bool) -> Bool {
        grantedBefore || promptedThisLaunch
    }

    /// Assinatura ad-hoc: a permissão não sobrevive a um build novo
    static let isAdHocSigned: Bool = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return flags & SecCodeSignatureFlags.adhoc.rawValue != 0 || dict[kSecCodeInfoCertificates as String] == nil
    }()

    private static func showStaleHint() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("O Menew está em Acessibilidade, mas o macOS não reconhece esta cópia")
        var info = L("Em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade, remova o Menew da lista (botão −) e adicione de novo (botão +). Depois, tente colar outra vez.")
        if isAdHocSigned {
            info += "\n\n" + L("Esta cópia é um build de desenvolvimento sem assinatura estável: cada build novo perde a permissão.")
        }
        alert.informativeText = info
        alert.addButton(withTitle: L("Abrir Ajustes"))
        alert.addButton(withTitle: L("OK"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
