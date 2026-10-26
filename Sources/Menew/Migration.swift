import Foundation

/// O app se chamava MeuMenu: traz histórico, notas e ajustes na primeira vez que o Menew abre.
enum Migration {
    static func run() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = base.appendingPathComponent("MeuMenu"), new = base.appendingPathComponent("Menew")
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromMeuMenu") else { return }
        defaults.set(true, forKey: "migratedFromMeuMenu")
        guard let oldDefaults = UserDefaults(suiteName: "com.matheusquost.meumenu") else { return }
        for key in ["menuBarStyle", "autoPaste", "maxItems", "ignoreConcealed", "paused", "ignoredApps"] {
            if let v = oldDefaults.object(forKey: key) { defaults.set(v, forKey: key) }
        }
    }
}
