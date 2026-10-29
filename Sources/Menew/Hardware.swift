import AppKit
import CoreAudio
import IOKit
import SwiftUI

// MARK: GPU e disco (IORegistry, sem permissão)

enum HardwareStats {
    /// Uso da GPU de 0 a 1 (a maior entre as GPUs); nil quando o Mac não informa
    static func gpuUtilization() -> Double? {
        var best: Double?
        forEach("IOAccelerator") { s in
            guard let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let pct = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { return }
            best = max(best ?? 0, min(max(pct / 100, 0), 1))
        }
        return best
    }

    /// Total de bytes lidos e gravados em todos os discos desde que o Mac ligou
    static func diskBytes() -> (read: UInt64, written: UInt64) {
        var r: UInt64 = 0, w: UInt64 = 0
        forEach("IOBlockStorageDriver") { s in
            guard let stats = IORegistryEntryCreateCFProperty(s, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { return }
            r += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            w += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (r, w)
    }

    private static func forEach(_ cls: String, _ body: (io_object_t) -> Void) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        while case let s = IOIteratorNext(iter), s != 0 {
            body(s)
            IOObjectRelease(s)
        }
    }
}

// MARK: Microfone e som (Core Audio, sem permissão)

enum AudioControl {
    static func isMuted(input: Bool) -> Bool {
        guard let dev = device(input: input) else { return false }
        if let m = getMute(dev, input: input) { return m }
        // Microfones sem "mudo" de verdade: volume zero conta como mudo
        return (getVolume(dev, input: input) ?? 1) == 0
    }

    @discardableResult
    static func setMuted(_ on: Bool, input: Bool) -> Bool {
        guard let dev = device(input: input) else { return false }
        if setMute(dev, input: input, on) { return true }
        let key = input ? "micVolumeBeforeMute" : "outVolumeBeforeMute"
        if on {
            if let v = getVolume(dev, input: input), v > 0 { UserDefaults.standard.set(v, forKey: key) }
            return setVolume(dev, input: input, 0)
        }
        let saved = UserDefaults.standard.object(forKey: key) as? Float ?? 0.75
        return setVolume(dev, input: input, saved)
    }

    private static func device(input: Bool) -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector, input: Bool, element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    /// Alguns aparelhos só têm o controle no canal 1 e 2, não no principal
    private static let elements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]

    private static func getMute(_ dev: AudioObjectID, input: Bool) -> Bool? {
        for el in elements {
            var addr = address(kAudioDevicePropertyMute, input: input, element: el)
            guard AudioObjectHasProperty(dev, &addr) else { continue }
            var v: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr { return v != 0 }
        }
        return nil
    }

    private static func setMute(_ dev: AudioObjectID, input: Bool, _ on: Bool) -> Bool {
        var done = false
        for el in elements {
            var addr = address(kAudioDevicePropertyMute, input: input, element: el)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(dev, &addr),
                  AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue else { continue }
            var v: UInt32 = on ? 1 : 0
            if AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr { done = true }
            if el == kAudioObjectPropertyElementMain && done { break }
        }
        return done
    }

    private static func getVolume(_ dev: AudioObjectID, input: Bool) -> Float? {
        for el in elements {
            var addr = address(kAudioDevicePropertyVolumeScalar, input: input, element: el)
            guard AudioObjectHasProperty(dev, &addr) else { continue }
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr { return v }
        }
        return nil
    }

    private static func setVolume(_ dev: AudioObjectID, input: Bool, _ value: Float) -> Bool {
        var done = false
        for el in elements {
            var addr = address(kAudioDevicePropertyVolumeScalar, input: input, element: el)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(dev, &addr),
                  AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue else { continue }
            var v = Float32(value)
            if AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr { done = true }
            if el == kAudioObjectPropertyElementMain && done { break }
        }
        return done
    }
}

/// Aviso rápido no meio da tela quando o microfone muda pelo atalho
@MainActor
enum MuteHUD {
    static func show(muted: Bool) {
        HUD.show(icon: muted ? "mic.slash.fill" : "mic.fill", color: muted ? .red : .green,
                 text: muted ? L("Microfone mudo") : L("Microfone ligado"))
    }
}

/// Confirmação curta perto da base da tela, sem roubar o foco (atalhos e paleta)
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(icon: String, color: Color, text: String) {
        let view = HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())

        let p = panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
            return p
        }()
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        p.contentView = host
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + f.height * 0.18, width: size.width, height: size.height), display: true)
        }
        p.alphaValue = 1
        p.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}

// MARK: Brilho das telas

/// Tela da Apple (embutida, Studio Display) via DisplayServices; monitor externo via DDC/CI.
struct ScreenInfo: Identifiable {
    enum Kind { case apple, ddc, unsupported }
    let id: CGDirectDisplayID
    let name: String
    let builtin: Bool
    var kind: Kind
    var brightness: Double
}

@MainActor
final class DisplayController: ObservableObject {
    @Published var screens: [ScreenInfo] = []
    /// Modo captura: mantém telas fictícias
    var isDemo = false

    private(set) var ddc: [CGDirectDisplayID: DDCService] = [:]
    private let writer = DDCWriter()

    func refresh() {
        guard !isDemo else { return }
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        // Espelhadas aparecem uma vez só
        ids = ids.filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }

        let externals = ids.filter { CGDisplayIsBuiltin($0) == 0 && !DisplayServices.canChange($0) }
        ddc = DDCService.match(displays: externals)

        screens = ids.map { id in
            let builtin = CGDisplayIsBuiltin(id) != 0
            let name = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }?
                .localizedName ?? (builtin ? L("Tela do Mac") : L("Monitor"))
            if DisplayServices.canChange(id), let b = DisplayServices.brightness(id) {
                return ScreenInfo(id: id, name: name, builtin: builtin, kind: .apple, brightness: b)
            }
            let old = screens.first { $0.id == id }
            return ScreenInfo(id: id, name: name, builtin: builtin, kind: ddc[id] != nil ? .ddc : .unsupported,
                              brightness: old?.brightness ?? 0.5)
        }
        // DDC é lento (dezenas de ms por leitura): lê fora da main
        for (id, svc) in ddc {
            Task.detached {
                let value = svc.read(vcp: 0x10)
                await MainActor.run {
                    guard let i = self.screens.firstIndex(where: { $0.id == id }) else { return }
                    if let (cur, mx) = value, mx > 0 {
                        self.screens[i].brightness = Double(cur) / Double(mx)
                        svc.maxValue = mx
                    } else if svc.maxValue == 0 {
                        // Não respondeu: o monitor não aceita DDC (ou está numa porta que não repassa)
                        self.screens[i].kind = .unsupported
                    }
                }
            }
        }
    }

    /// `Menew --hardware`: diagnóstico de telas, GPU, disco e áudio (útil em relatos de bug)
    static func printReport() {
        let c = DisplayController()
        c.refresh()
        print("gpu:", HardwareStats.gpuUtilization().map { Fmt.pct($0) } ?? "n/a")
        print("disk bytes:", HardwareStats.diskBytes())
        for (id, svc) in c.ddc { print("ddc \(id) raw:", svc.read(vcp: 0x10).map { "\($0.0)/\($0.1)" } ?? "no reply") }
        print("mic muted:", AudioControl.isMuted(input: true), "sound muted:", AudioControl.isMuted(input: false))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for s in c.screens {
                print("screen \(s.id) \(s.name) builtin=\(s.builtin) kind=\(s.kind) brightness=\(Fmt.pct(s.brightness))")
            }
            exit(0)
        }
    }

    func set(_ value: Double, for id: CGDirectDisplayID) {
        guard let i = screens.firstIndex(where: { $0.id == id }) else { return }
        screens[i].brightness = value
        guard !isDemo else { return }
        switch screens[i].kind {
        case .apple: DisplayServices.setBrightness(id, value)
        case .ddc: if let svc = ddc[id] { writer.write(svc, value: value) }
        case .unsupported: break
        }
    }
}

/// Funções privadas do macOS carregadas em tempo de execução: se sumirem numa versão nova, o recurso só não aparece
private enum DisplayServices {
    private typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    nonisolated(unsafe) private static let canFn = sym("DisplayServicesCanChangeBrightness", CanFn.self)
    nonisolated(unsafe) private static let getFn = sym("DisplayServicesGetBrightness", GetFn.self)
    nonisolated(unsafe) private static let setFn = sym("DisplayServicesSetBrightness", SetFn.self)

    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    static func canChange(_ id: CGDirectDisplayID) -> Bool { canFn?(id) ?? false }

    static func brightness(_ id: CGDirectDisplayID) -> Double? {
        var v: Float = 0
        guard let getFn, getFn(id, &v) == 0 else { return nil }
        return Double(v)
    }

    static func setBrightness(_ id: CGDirectDisplayID, _ v: Double) {
        _ = setFn?(id, Float(min(max(v, 0), 1)))
    }
}

/// Um monitor externo falando DDC/CI pelo cabo (Apple Silicon: IOAVService)
final class DDCService: @unchecked Sendable {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    nonisolated(unsafe) private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    nonisolated(unsafe) private static let create = sym("IOAVServiceCreateWithService", CreateFn.self)
    nonisolated(unsafe) private static let readI2C = sym("IOAVServiceReadI2C", I2CFn.self)
    nonisolated(unsafe) private static let writeI2C = sym("IOAVServiceWriteI2C", I2CFn.self)

    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let iokit, let p = dlsym(iokit, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private let service: CFTypeRef
    private let lock = NSLock()
    var maxValue: UInt16 = 0

    private init(_ service: CFTypeRef) { self.service = service }

    /// Liga cada monitor externo ao seu IOAVService pelo fabricante e modelo do EDID
    static func match(displays: [CGDirectDisplayID]) -> [CGDirectDisplayID: DDCService] {
        guard !displays.isEmpty, let create, readI2C != nil, writeI2C != nil else { return [:] }
        var found: [(vendor: Int?, model: Int?, svc: DDCService)] = []
        var lastAttrs: [String: Any]?

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        var iter: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iter) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iter); IOObjectRelease(root) }
        while case let entry = IOIteratorNext(iter), entry != 0 {
            defer { IOObjectRelease(entry) }
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuf)
            let name = String(cString: nameBuf)
            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                let attrs = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
                lastAttrs = attrs?["ProductAttributes"] as? [String: Any]
            } else if name == "DCPAVServiceProxy" {
                let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String
                guard location == "External", let svc = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
                found.append((lastAttrs?["LegacyManufacturerID"] as? Int, lastAttrs?["ProductID"] as? Int, DDCService(svc)))
            }
        }

        var result: [CGDirectDisplayID: DDCService] = [:]
        var remaining = displays
        for f in found {
            if let i = remaining.firstIndex(where: { Int(CGDisplayVendorNumber($0)) == f.vendor && Int(CGDisplayModelNumber($0)) == f.model }) {
                result[remaining.remove(at: i)] = f.svc
            }
        }
        // Sem EDID para comparar: um monitor e um serviço sobrando são o mesmo
        let unused = found.filter { f in !result.values.contains { $0 === f.svc } }
        if remaining.count == 1, unused.count == 1 { result[remaining[0]] = unused[0].svc }
        return result
    }

    /// Valor atual e máximo de um código VCP (0x10 = brilho)
    func read(vcp: UInt8) -> (UInt16, UInt16)? {
        guard let readI2C = Self.readI2C, let writeI2C = Self.writeI2C else { return nil }
        lock.lock(); defer { lock.unlock() }
        var req: [UInt8] = [0x82, 0x01, vcp, 0]
        req[3] = 0x6E ^ 0x51 ^ req[0] ^ req[1] ^ req[2]
        for _ in 0..<4 {
            usleep(10_000)
            guard writeI2C(service, 0x37, 0x51, &req, UInt32(req.count)) == kIOReturnSuccess else { continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            guard readI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == kIOReturnSuccess else { continue }
            var chk: UInt8 = 0x50
            for b in reply[0..<10] { chk ^= b }
            guard chk == reply[10], reply[2] == 0x02, reply[3] == 0x00 else { continue }
            let mx = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let cur = UInt16(reply[8]) << 8 | UInt16(reply[9])
            return (cur, mx)
        }
        return nil
    }

    func write(vcp: UInt8, value: UInt16) {
        guard let writeI2C = Self.writeI2C else { return }
        lock.lock(); defer { lock.unlock() }
        var data: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        data[5] = 0x6E ^ 0x51 ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4]
        // Alguns monitores ignoram a primeira mensagem
        for _ in 0..<2 {
            usleep(10_000)
            _ = writeI2C(service, 0x37, 0x51, &data, UInt32(data.count))
        }
    }
}

/// Junta os movimentos do slider: o monitor só recebe o valor mais recente
private final class DDCWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "menew.ddc")
    private let lock = NSLock()
    private var pending: [ObjectIdentifier: (DDCService, Double)] = [:]

    func write(_ svc: DDCService, value: Double) {
        let key = ObjectIdentifier(svc)
        lock.lock()
        let scheduled = pending[key] != nil
        pending[key] = (svc, value)
        lock.unlock()
        guard !scheduled else { return }
        queue.async { [self] in
            lock.lock()
            let item = pending.removeValue(forKey: key)
            lock.unlock()
            guard let (svc, v) = item else { return }
            let mx = svc.maxValue > 0 ? svc.maxValue : 100
            svc.write(vcp: 0x10, value: UInt16((v * Double(mx)).rounded()))
        }
    }
}
