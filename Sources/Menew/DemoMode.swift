import AppKit
import ObjectiveC

/// `Menew --demo`: o app inteiro, rodando de verdade, só com dados fictícios. Serve para gravar vídeos de divulgação.
/// Nada do usuário é lido ou gravado: os arquivos vão para uma pasta temporária (apagada ao sair), os ajustes para
/// um domínio próprio (`com.matheusquost.menew.demo`) e o clipboard, a Memória automática, o Spotlight, os widgets,
/// a busca de atualizações e os agentes de IA ficam desligados. Um travamento deixa os dados reais como estavam.
enum DemoMode {
    static let flag = "--demo"
    static let isOn = CommandLine.arguments.contains(flag)
    /// Ajustes do modo demo, separados dos reais. `defaults delete com.matheusquost.menew.demo` volta ao padrão.
    static let defaultsSuite = "com.matheusquost.menew.demo"
    /// No lugar de ~/Library/Application Support/Menew
    static let dataDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("Menew-demo-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    fileprivate static let defaults = UserDefaults(suiteName: defaultsSuite) ?? UserDefaults()

    /// Antes de tudo (antes de qualquer `UserDefaults.standard`): troca os ajustes, a pasta e o idioma
    @MainActor static func prepare() {
        guard isOn else { return }
        // Nomes de apps, datas e durações seguem o idioma do sistema, não o do Menew: reabre o processo com o mesmo
        // idioma em `-AppleLanguages`, para o vídeo não misturar línguas
        let args = CommandLine.arguments
        if !args.contains("-AppleLanguages"), let exe = Bundle.main.executablePath {
            let lang = args.firstIndex(of: "-language").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "en"
            let system = ["pt": "pt-BR", "zh": "zh-Hans"][lang] ?? lang
            var argv = (args + ["-AppleLanguages", "(\(system))"]).map { strdup($0) } + [nil]
            execv(exe, &argv)
            // Se não deu, segue assim mesmo
        }
        // Um Menew de verdade aberto ao mesmo tempo dividiria atalhos e ícones da barra: melhor sair dele antes
        if let id = Bundle.main.bundleIdentifier {
            let me = ProcessInfo.processInfo.processIdentifier
            if NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != me && !$0.isTerminated }) {
                FileHandle.standardError.write(Data("Menew --demo: quit the running Menew first.\n".utf8))
                exit(1)
            }
        }
        // `UserDefaults.standard` (e @AppStorage) passa a ser o domínio do demo: os ajustes reais nem são lidos
        if let real = class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard)),
           let demo = class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.menewDemoStandard)) {
            method_exchangeImplementations(real, demo)
        }
        // Inglês, a não ser que outro idioma venha na linha de comando (`-language de`)
        if !CommandLine.arguments.contains("-language") { defaults.set("en", forKey: "language") }
        // Pasta nova a cada abertura; as que sobraram de um travamento vão embora
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        for name in (try? fm.contentsOfDirectory(atPath: tmp.path)) ?? [] where name.hasPrefix("Menew-demo-") {
            try? fm.removeItem(at: tmp.appendingPathComponent(name))
        }
        try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            try? FileManager.default.removeItem(at: DemoMode.dataDir)
        }
    }

    /// Os dados fictícios das capturas de tela (`--snapshot`), agora no app rodando
    @MainActor static func populate(monitor: SystemMonitor, toolbox: Toolbox, internet: InternetInfo) {
        // A agenda aparece com as reuniões fictícias (a de verdade nunca é lida)
        UserDefaults.standard.register(defaults: [MeetingStore.key: true])
        MeetingStore.shared.showDemo()
        NetUsage.shared.showDemo()
        AccessoryMonitor.shared.showDemo()
        SystemHistory.shared.showDemo()
        ScreenTime.shared.showDemo()
        Sensors.shared.showDemo()
        WorldClock.shared.demo()
        ProfileStore.shared.demo()
        AutomationStore.shared.demo()
        ShelfStore.shared.demo()
        MemoryStore.shared.showDemo()
        BatteryWear.shared.showDemo()
        BatteryLog.shared.set(BatteryLog.demo)
        RecordingStore.shared.showDemo()
        AgentUsageStore.shared.showDemo()
        AgentHub.shared.showDemo()
        fakeDisplays(toolbox)
        fakeInternet(internet)
        fakeMachine(monitor)
    }

    /// Telas inventadas no lugar das conectadas
    @MainActor static func fakeDisplays(_ toolbox: Toolbox) {
        toolbox.displays.isDemo = true
        toolbox.displays.screens = [
            ScreenInfo(id: 1, name: L("Tela do Mac"), builtin: true, kind: .apple, brightness: 0.72),
            ScreenInfo(id: 2, name: "DELL P2419H", builtin: false, kind: .ddc, brightness: 0.5),
        ]
    }

    /// IP público, teste de velocidade e aparelhos Bluetooth (os nomes reais costumam ter o nome da pessoa)
    @MainActor static func fakeInternet(_ internet: InternetInfo) {
        internet.isDemo = true
        internet.speed = .done(SpeedResult(down: 224, up: 146, latency: 21, rpm: 425))
        internet.publicIP = "189.0.113.42"
        internet.devices = [
            BTDevice(name: "AirPods Pro", kind: .airpods, levels: [(L("E"), 90), (L("D"), 88), (L("Estojo"), 54)]),
            BTDevice(name: "Magic Mouse", kind: .mouse, levels: [("", 17)]),
        ]
    }

    /// Rede, processos, memória e bateria fictícios; CPU e tráfego seguem os reais para os gráficos se mexerem
    @MainActor static func fakeMachine(_ monitor: SystemMonitor) {
        monitor.isDemo = true
        monitor.localIP = "192.168.0.12"
        monitor.battery = BatteryInfo(percent: 80, charging: false, onAC: true, minutesLeft: nil)
        monitor.batteryHealth = BatteryHealth(cycles: 112, healthPercent: 96, temperature: nil, adapterWatts: 70, systemWatts: 8.4)
        monitor.coreLoads = [0.12, 0.08, 0.15, 0.05, 0.09, 0.11, 0.42, 0.31, 0.18, 0.25]
        monitor.memPressure = .normal
        monitor.memTotal = 16 << 30
        monitor.memBreakdown = MemoryBreakdown(app: 6_400 << 20, wired: 2_100 << 20, compressed: 1_300 << 20)
        monitor.memUsed = monitor.memBreakdown.app + monitor.memBreakdown.wired + monitor.memBreakdown.compressed
        monitor.swapUsed = 0
        monitor.topProcesses = [
            ProcInfo(name: "Safari", cpu: 18.4, memKB: 1_450_000),
            ProcInfo(name: "WindowServer", cpu: 9.2, memKB: 420_000),
            ProcInfo(name: "Xcode", cpu: 6.1, memKB: 2_100_000),
            ProcInfo(name: "Music", cpu: 2.3, memKB: 310_000),
            ProcInfo(name: "Finder", cpu: 0.8, memKB: 160_000),
        ]
    }
}

/// Pasta de dados do Menew: a real ou, no modo demo, a temporária
enum AppData {
    static var dir: URL {
        if DemoMode.isOn { return DemoMode.dataDir }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Menew", isDirectory: true)
    }
}

extension UserDefaults {
    /// Trocado com `standard` no modo demo (ver `DemoMode.prepare`)
    @objc class var menewDemoStandard: UserDefaults { DemoMode.defaults }
}
