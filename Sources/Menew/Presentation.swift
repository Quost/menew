import AppKit
import CoreAudio
import SwiftUI

// MARK: Saída e entrada de som

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let name: String
    let transport: UInt32

    func icon(input: Bool) -> String {
        let n = name.lowercased()
        if n.contains("airpods") { return "airpods" }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeBuiltIn: return input ? "mic.fill" : "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return "waveform"
        default: return input ? "mic.fill" : "hifispeaker.fill"
        }
    }
}

/// Fones, caixas, AirPods e microfones do Mac. Trocar aqui é o mesmo que em Ajustes → Som.
@MainActor
final class AudioRouter: ObservableObject {
    static let shared = AudioRouter()
    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var inputs: [AudioDevice] = []
    @Published private(set) var output: AudioObjectID = 0
    @Published private(set) var input: AudioObjectID = 0
    private var listening = false

    private init() {}

    /// Lê a lista e passa a acompanhar mudanças (fone conectado, troca feita em Ajustes)
    func start() {
        refresh()
        guard !listening else { return }
        listening = true
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var addr = Self.global(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
                MainActor.assumeIsolated { AudioRouter.shared.refresh() }
            }
        }
    }

    func refresh() {
        let all = Self.deviceIDs()
        outputs = all.filter { Self.channels($0, input: false) > 0 }.compactMap(Self.device)
        inputs = all.filter { Self.channels($0, input: true) > 0 }.compactMap(Self.device)
        output = Self.defaultDevice(input: false)
        input = Self.defaultDevice(input: true)
    }

    var currentOutput: AudioDevice? { outputs.first { $0.id == output } }
    var currentInput: AudioDevice? { inputs.first { $0.id == input } }

    func select(_ device: AudioDevice, input: Bool) {
        var id = device.id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = Self.global(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &id)
        if !input {
            // Os sons de alerta vão junto, como em Ajustes → Som
            var alerts = Self.global(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &alerts, 0, nil, size, &id)
        }
        refresh()
        HUD.show(icon: device.icon(input: input), color: .blue, text: device.name)
    }

    // MARK: CoreAudio

    private static func global(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func deviceIDs() -> [AudioObjectID] {
        var addr = global(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultDevice(input: Bool) -> AudioObjectID {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = global(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func channels(_ id: AudioObjectID, input: Bool) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func device(_ id: AudioObjectID) -> AudioDevice? {
        var hiddenAddr = global(kAudioDevicePropertyIsHidden)
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(id, &hiddenAddr, 0, nil, &size, &hidden) == noErr, hidden != 0 { return nil }
        var nameAddr = global(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &size, &name) == noErr,
              let n = name?.takeRetainedValue() as String?, !n.hasPrefix("CADefaultDeviceAggregate") else { return nil }
        var transportAddr = global(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &transportAddr, 0, nil, &size, &transport)
        return AudioDevice(id: id, name: n, transport: transport)
    }
}

/// Seção "Som" na aba Ações: saída e microfone, cada um com um menu
struct AudioSection: View {
    @ObservedObject var router = AudioRouter.shared

    var body: some View {
        VStack(spacing: 0) {
            row(input: false)
            Rectangle().fill(Theme.cardStroke).frame(height: 0.5).padding(.leading, 52)
            row(input: true)
        }
        .padding(.vertical, 4)
        .glass()
        .onAppear { router.start() }
    }

    private func row(input: Bool) -> some View {
        let current = input ? router.currentInput : router.currentOutput
        let list = input ? router.inputs : router.outputs
        let color: Color = input ? .red : .blue
        return HStack(spacing: 12) {
            Image(systemName: current?.icon(input: input) ?? (input ? "mic.fill" : "speaker.wave.2.fill"))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(input ? L("Microfone") : L("Saída de som")).font(.system(size: 12.5, weight: .semibold))
                Text(current?.name ?? L("Nenhum")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(list) { d in
                    Button {
                        router.select(d, input: input)
                    } label: {
                        Label(d.name, systemImage: d.id == current?.id ? "checkmark" : d.icon(input: input))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(L("Trocar")).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .glass(in: Capsule(), interactive: true)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .disabled(list.count < 2)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// MARK: Modo apresentação

/// Um clique antes de apresentar ou compartilhar a tela: esconde os ícones da mesa, mantém o Mac acordado,
/// pausa o clipboard e deixa só o ícone na barra de menus. Ao desligar, desfaz só o que ele mesmo mudou.
@MainActor
final class PresentationMode: ObservableObject {
    static let shared = PresentationMode()
    @Published private(set) var isOn = false
    var onChange: (() -> Void)?
    private weak var toolbox: Toolbox?
    private var changed: Set<String> = []

    func attach(_ toolbox: Toolbox) { self.toolbox = toolbox }

    func toggle() { set(!isOn) }

    func set(_ on: Bool) {
        guard on != isOn, let tb = toolbox else { return }
        if on {
            changed = []
            if !tb.desktopIconsHidden { tb.toggleDesktopIcons(); changed.insert("desktop") }
            if !tb.keepAwake { tb.setKeepAwake(true); changed.insert("awake") }
            if !ClipboardManager.isPaused { ClipboardManager.pause(minutes: nil); changed.insert("clipboard") }
        } else {
            if changed.contains("desktop"), tb.desktopIconsHidden { tb.toggleDesktopIcons() }
            if changed.contains("awake") { tb.setKeepAwake(false) }
            if changed.contains("clipboard") { ClipboardManager.resume() }
            changed = []
        }
        isOn = on
        onChange?()
        AutomationStore.shared.presentationChanged(started: on)
        HUD.show(icon: on ? "play.rectangle.fill" : "rectangle.slash", color: on ? .green : .secondary,
                 text: on ? L("Modo apresentação ligado") : L("Modo apresentação desligado"))
    }
}
