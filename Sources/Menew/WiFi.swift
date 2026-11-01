import CoreWLAN
import SwiftUI

/// Detalhes do Wi-Fi (como o Wireless Diagnostics): sinal, ruído, velocidade do link, canal, faixa e padrão.
/// O nome da rede pede permissão de localização no macOS, então o Menew não mostra (nem pede).
struct WiFiInfo: Equatable {
    let rssi: Int
    let noise: Int
    let rate: Double
    let channel: Int
    let band: String
    let width: Int
    let standard: String

    var snr: Int { rssi - noise }

    /// Pela relação sinal/ruído, que diz mais que o sinal sozinho
    var quality: (label: String, color: Color, bars: Int) {
        switch snr {
        case 40...: (L("Excelente"), .green, 4)
        case 25..<40: (L("Bom"), .green, 3)
        case 15..<25: (L("Razoável"), .orange, 2)
        default: (L("Fraco"), .red, 1)
        }
    }

    static func read() -> WiFiInfo? {
        guard let i = CWWiFiClient.shared().interface(), i.powerOn(), let ch = i.wlanChannel(), i.rssiValue() != 0 else { return nil }
        let band: String = switch ch.channelBand {
        case .band2GHz: "2,4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: "—"
        }
        let width: Int = switch ch.channelWidth {
        case .width20MHz: 20
        case .width40MHz: 40
        case .width80MHz: 80
        case .width160MHz: 160
        default: 0
        }
        let standard: String = switch i.activePHYMode() {
        case .mode11ax: ch.channelBand == .band6GHz ? "Wi-Fi 6E" : "Wi-Fi 6"
        case .mode11ac: "Wi-Fi 5"
        case .mode11n: "Wi-Fi 4"
        case .mode11a, .mode11b, .mode11g: "802.11a/b/g"
        default: i.activePHYMode().rawValue >= 7 ? "Wi-Fi 7" : "—"
        }
        return WiFiInfo(rssi: i.rssiValue(), noise: i.noiseMeasurement(), rate: i.transmitRate(), channel: ch.channelNumber,
                        band: band, width: width, standard: standard)
    }
}

/// Linha do Wi-Fi no cartão de rede; some com o Wi-Fi desligado ou no cabo
struct WiFiRow: View {
    @State private var info: WiFiInfo?
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let w = info {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi").foregroundStyle(w.quality.color)
                        Text("Wi-Fi").font(.system(size: 12, weight: .semibold))
                        Text(w.quality.label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(w.quality.color)
                        Spacer()
                        Text("\(w.standard) · \(w.band)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 0) {
                        stat(L("Sinal"), "\(w.rssi) dBm")
                        stat(L("Ruído"), "\(w.noise) dBm")
                        stat(L("Velocidade"), "\(Int(w.rate)) Mbps")
                        stat(L("Canal"), w.width > 0 ? "\(w.channel) · \(w.width) MHz" : "\(w.channel)")
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                .help(L("Relação sinal/ruído: %d dB. Acima de 25 dB é uma boa conexão.", w.snr))
            }
        }
        .onAppear { info = WiFiInfo.read() }
        .onReceive(timer) { _ in info = WiFiInfo.read() }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
