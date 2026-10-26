import AppKit

/// Abre uma issue no GitHub já preenchida com as versões. Nada é enviado sozinho:
/// a pessoa vê o formulário no navegador antes de enviar.
enum Feedback {
    private static let repo = "https://github.com/Quost/menew"

    static func reportBug() { open(template: "bug_report.yml", fields: environment) }
    static func suggestIdea() { open(template: "feature_request.yml", fields: ["version": appVersion]) }
    static func openRepo() { NSWorkspace.shared.open(URL(string: repo)!) }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private static var environment: [String: String] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "version": appVersion,
            "macos": "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "mac": "\(chip) (\(model))",
            "language": L10n.current.nativeName,
        ]
    }

    private static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    private static var chip: String {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return translated == 1 ? "Apple Silicon (Rosetta)" : "Intel"
        #endif
    }

    private static func open(template: String, fields: [String: String]) {
        var c = URLComponents(string: "\(repo)/issues/new")!
        c.queryItems = [URLQueryItem(name: "template", value: template)] +
            fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}
