import SwiftUI
import AppKit
import CoreImage

/// Floating window controller managing the Pairing modal so it remains visible
/// while the user scans the QR code from their phone.
public final class PairingWindowController: ObservableObject {
    public static let shared = PairingWindowController()
    private var window: NSPanel?

    @Published public private(set) var activePin: String?

    private init() {}

    /// Present the floating pairing modal.
    public func showPairingWindow() {
        let initialPin = String(format: "%06d", Int.random(in: 100000...999999))
        self.activePin = initialPin

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

    /// Update active PIN when user refreshes PIN in modal
    public func updateActivePin(_ newPin: String) {
        DispatchQueue.main.async {
            self.activePin = newPin
        }
    }

    /// Invoked when pairing handshake succeeds from remote device
    public func onPairingSuccess() {
        DispatchQueue.main.async {
            NSSound(named: "Glass")?.play()
            self.closePairingWindow()
        }
    }

    /// Close and release the floating pairing modal.
    public func closePairingWindow() {
        activePin = nil
        window?.close()
        window = nil
    }
}

struct PairingModalView: View {
    var onClose: () -> Void

    @State private var pin: String = PairingWindowController.shared.activePin ?? String(format: "%06d", Int.random(in: 100000...999999))
    @State private var qrImage: NSImage?

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                if let logoImg = loadLogoImage() {
                    Image(nsImage: logoImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                }

                VStack(spacing: 2) {
                    Text("Pair with Android")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Scan this QR code using Corda on your phone")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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
                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
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
        let newPin = String(format: "%06d", Int.random(in: 100000...999999))
        pin = newPin
        PairingWindowController.shared.updateActivePin(newPin)
        generateQRCode()
    }

    private func generateQRCode() {
        let computerName = Host.current().localizedName ?? "Mac"
        let fingerprint = (try? CryptoManager.shared.getPublicKeyFingerprint()) ?? ""
        let devId = UserDefaults.standard.string(forKey: "com.corda.mac.local_device_id") ?? UUID().uuidString

        // Compact URI format with host IP for zero-friction direct socket connection
        let encodedName = computerName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"
        var uriString = "corda://pair?id=\(devId)&name=\(encodedName)&fp=\(fingerprint)&pin=\(pin)"
        if let hostIP = getLocalIPAddress() {
            uriString += "&host=\(hostIP)&port=54321"
        }

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

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" || name == "bridge0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if !ip.isEmpty && ip != "127.0.0.1" {
                        address = ip
                        break
                    }
                }
            }
        }
        return address
    }

    private func loadLogoImage() -> NSImage? {
        let candidateNames = ["logo_corda", "corda_logo_icon"]
        for name in candidateNames {
            if let mainUrl = Bundle.main.url(forResource: name, withExtension: "png"),
               let img = NSImage(contentsOf: mainUrl) {
                return img
            }
            #if SWIFT_PACKAGE
            if let url = Bundle.module.url(forResource: name, withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                return img
            }
            #endif
            if let img = NSImage(named: name) {
                return img
            }
        }
        let fallbackPaths = [
            "macos/CordaMac/Resources/logo_corda.png",
            "assets/logo-corda.png",
            "macos/CordaMac/Resources/corda_logo_icon.png"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        return nil
    }
}
