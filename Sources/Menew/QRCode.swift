import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import Vision

/// QR codes: ler um QR da tela (como a captura de texto) e mostrar o QR de um texto, link ou Wi-Fi para o celular ler.
/// Tudo no Mac: Vision para ler, Core Image para gerar.
@MainActor
enum QRCode {
    // MARK: Ler da tela

    /// Você seleciona a área com o QR; o conteúdo vai para o clipboard. Links não abrem sozinhos (um QR pode enganar).
    static func scanScreen() {
        guard ScreenCapture.hasAccess() else { return }
        NotificationCenter.default.post(name: .closeMenu, object: nil)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("menew-qr-\(UUID().uuidString).png")
        Task {
            let found: [String]? = await Task.detached {
                Shell.run("/usr/sbin/screencapture", ["-i", "-x", file.path])
                defer { try? FileManager.default.removeItem(at: file) }
                guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }  // esc
                return read(image)
            }.value
            guard let found else { return }
            guard let first = found.first else {
                HUD.show(icon: "qrcode.viewfinder", color: .orange, text: L("Nenhum QR code encontrado"))
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(first, forType: .string)
            let isLink = URL(string: first)?.scheme?.hasPrefix("http") == true
            HUD.show(icon: "qrcode.viewfinder", color: .green,
                     text: isLink ? L("Link do QR copiado") : L("Conteúdo do QR copiado"), duration: 1.6)
        }
    }

    /// Conteúdo dos códigos na imagem (QR, Aztec, Data Matrix, PDF417)
    nonisolated static func read(_ image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr, .aztec, .dataMatrix, .pdf417, .microQR]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }

    // MARK: Gerar

    /// QR em alta resolução, sem borrar ao ampliar
    nonisolated static func image(for text: String, size: CGFloat = 1024) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scale = size / out.extent.width
        let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    /// Formato que câmeras de iPhone e Android entendem para entrar no Wi-Fi
    static func wifiPayload(name: String, password: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: ":", with: "\\:").replacingOccurrences(of: "\"", with: "\\\"")
        }
        return password.isEmpty ? "WIFI:T:nopass;S:\(esc(name));;" : "WIFI:T:WPA;S:\(esc(name));P:\(esc(password));;"
    }

    private static var window: NSPanel?
    private static let model = QRModel()

    /// Janela com o QR. `text` vazio: usa o que estiver copiado.
    static func show(text: String? = nil, wifi: Bool = false) {
        model.mode = wifi ? .wifi : .text
        if let text { model.text = text } else if !wifi { model.text = TextTransform.clipboardText() ?? "" }
        let w = window ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
                            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.contentView = NSHostingView(rootView: QRView(model: model) { [weak p] in p?.close() })
            return p
        }()
        window = w
        if !w.isVisible { w.center() }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class QRModel: ObservableObject {
    enum Mode: Hashable { case text, wifi }
    @Published var mode: Mode = .text
    @Published var text = ""
    @Published var wifiName = ""
    @Published var wifiPassword = ""

    var payload: String {
        mode == .text ? text.trimmingCharacters(in: .whitespacesAndNewlines)
            : (wifiName.isEmpty ? "" : QRCode.wifiPayload(name: wifiName, password: wifiPassword))
    }
}

struct QRView: View {
    @ObservedObject var model: QRModel
    var close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            GlassSegmented(selection: $model.mode, options: [
                .init(value: .text, icon: "text.alignleft", help: L("Texto ou link")),
                .init(value: .wifi, icon: "wifi", help: L("Wi-Fi")),
            ], expand: false)
            Group {
                if let img = model.payload.isEmpty ? nil : QRCode.image(for: model.payload, size: 600) {
                    Image(nsImage: img).interpolation(.none).resizable().aspectRatio(1, contentMode: .fit)
                        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(.white))
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06))
                        .overlay(Image(systemName: "qrcode").font(.system(size: 60, weight: .light)).foregroundStyle(.tertiary))
                }
            }
            .frame(width: 240, height: 240)
            if model.mode == .text {
                TextField(L("Texto ou link"), text: $model.text, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder)
            } else {
                TextField(L("Nome da rede"), text: $model.wifiName).textFieldStyle(.roundedBorder)
                SecureField(L("Senha"), text: $model.wifiPassword).textFieldStyle(.roundedBorder)
            }
            Text(model.mode == .wifi ? L("Aponte a câmera do celular para entrar na rede.") : L("Aponte a câmera do celular para abrir no telefone."))
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                PillButton(title: L("Fechar"), icon: "xmark", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                PillButton(title: L("Copiar imagem"), icon: "doc.on.doc", primary: true) {
                    guard let img = QRCode.image(for: model.payload) else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([img])
                    HUD.show(icon: "qrcode", color: .green, text: L("QR code copiado"))
                }
                .disabled(model.payload.isEmpty)
            }
        }
        .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 16)
        .frame(width: 360)
        .background(VisualEffect(material: .popover).ignoresSafeArea())
    }
}
