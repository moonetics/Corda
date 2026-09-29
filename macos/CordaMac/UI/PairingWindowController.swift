import SwiftUI
import AppKit
import CoreImage

/// Floating window controller managing the Pairing modal so it remains visible
/// while the user scans the QR code from their phone.
public final class PairingWindowController {
    public static let shared = PairingWindowController()
    private var window: NSPanel?

    private init() {}

    /// Present the floating pairing modal.
    public func showPairingWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 440),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pair New Device"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PairingModalView(onClose: { [weak self] in
            self?.closePairingWindow()
        }))

        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close and release the floating pairing modal.
    public func closePairingWindow() {
        window?.close()
        window = nil
    }
}

struct PairingModalView: View {
    var onClose: () -> Void

    @State private var pin: String = String(format: "%06d", Int.random(in: 100000...999999))
    @State private var qrImage: NSImage?

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 4) {
                Text("Pair with Android")
                    .font(.system(size: 15, weight: .bold))
                Text("Scan this QR Code using Corda on your phone")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // QR Code Container
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)

                if let img = qrImage {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 190, height: 190)

            // PIN Display
            VStack(spacing: 2) {
                Text("VERIFICATION PIN")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.5)

                Text(formattedPin(pin))
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.52, blue: 1.0),
                                Color(red: 0.0, green: 0.82, blue: 0.83)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .padding(.vertical, 2)

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button(action: regeneratePin) {
                    Label("Refresh PIN", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: onClose) {
                    Text("Done")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 320, height: 420)
        .onAppear {
            generateQRCode()
        }
    }

    private func regeneratePin() {
        pin = String(format: "%06d", Int.random(in: 100000...999999))
        generateQRCode()
    }

    private func generateQRCode() {
        let computerName = Host.current().localizedName ?? "Mac"
        let fingerprint = (try? CryptoManager.shared.getPublicKeyFingerprint()) ?? ""
        let devId = UserDefaults.standard.string(forKey: "com.corda.mac.local_device_id") ?? UUID().uuidString

        // Compact URI format
        let encodedName = computerName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"
        let uriString = "corda://pair?id=\(devId)&name=\(encodedName)&fp=\(fingerprint)&pin=\(pin)"

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(Data(uriString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return }
        
        let rep = NSCIImageRep(ciImage: outputImage)
        let nsImage = NSImage(size: NSSize(width: 190, height: 190))
        nsImage.addRepresentation(rep)

        self.qrImage = nsImage
    }

    private func formattedPin(_ pin: String) -> String {
        guard pin.count == 6 else { return pin }
        let index3 = pin.index(pin.startIndex, offsetBy: 3)
        return "\(pin[..<index3]) \(pin[index3...])"
    }
}
