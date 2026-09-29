import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Clean & Minimalist macOS Sonoma popover displayed when clicking Corda in the Menu Bar.
/// Designed with solid neutral surfaces, zero glassmorphism, high contrast, and accessible hierarchy.
public struct MenuBarPopupView: View {
    @ObservedObject private var discovery = BonjourDiscoveryManager.shared
    @ObservedObject private var clipboard = MacClipboardObserver.shared
    @ObservedObject private var server = ControlSessionServer.shared
    @ObservedObject private var fileStreaming = FileStreamingManager.shared

    @State private var isDropTargeted: Bool = false
    @State private var droppedFilesSummary: String? = nil
    @State private var showingSettings: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Logo, Title, Subtitle, and Quick Actions
            HStack(spacing: 10) {
                if let logoImg = loadLogoImage() {
                    Image(nsImage: logoImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Corda")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Mac & Android Continuity")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingSettings.toggle()
                        }
                    }) {
                        Image(systemName: showingSettings ? "xmark.circle.fill" : "gearshape.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(showingSettings ? .secondary : Color(red: 0.04, green: 0.52, blue: 1.0))
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(showingSettings ? "Close Settings" : "Settings & Storage")

                    Button(action: {
                        PairingWindowController.shared.showPairingWindow()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Pair New Device")
                }
            }

            Divider()

            if showingSettings {
                MacSettingsView(onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingSettings = false
                    }
                })
            } else {
                // Connected & Nearby Devices Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("CONNECTED DEVICES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.1)

                    if server.connectedPeers.isEmpty && discovery.discoveredDevices.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Searching for Android device...")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("Open Corda on your phone to connect")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                    } else {
                        ForEach(server.connectedPeers) { peer in
                            ConnectedPeerRowView(peer: peer)
                        }
                        ForEach(discovery.discoveredDevices.filter { dev in
                            !server.connectedPeers.contains { $0.name == dev.name || $0.fingerprint == dev.fingerprint }
                        }) { device in
                            DeviceRowView(device: device)
                        }
                    }

                    if discovery.isPossibleAPIsolation && discovery.discoveredDevices.isEmpty && server.connectedPeers.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.orange)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Possible Wi-Fi AP Isolation")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.orange)
                                Text("This Wi-Fi network may prevent peer-to-peer connections.")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.orange.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                                )
                        )
                    }
                }

                // Active File Transfer Progress Card
                if let transfer = fileStreaming.activeTransfer {
                    ActiveTransferCardView(transfer: transfer)
                }

                // Drop or Click to Send Files (Solid Minimalist Dropzone)
                VStack(alignment: .leading, spacing: 6) {
                    Text("DROP OR CLICK TO SEND FILES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.1)

                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isDropTargeted
                                    ? Color(red: 0.04, green: 0.52, blue: 1.0)
                                    : Color.primary.opacity(0.14),
                                style: StrokeStyle(lineWidth: isDropTargeted ? 1.5 : 1, dash: [5, 4])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isDropTargeted ? Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.08) : Color.primary.opacity(0.03))
                            )

                        VStack(spacing: 4) {
                            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "arrow.up.doc.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                            Text(droppedFilesSummary ?? (isDropTargeted ? "Release to send files" : "Drag files or click to send"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(droppedFilesSummary != nil ? Color.primary : Color.secondary)

                            if droppedFilesSummary == nil {
                                Text("Supports photos, videos & documents")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 14)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectAndSendFiles()
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        handleDroppedItems(providers)
                        return true
                    }
                }

                // Live Clipboard Status Card
                if let text = clipboard.lastCopiedText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RECENT CLIPBOARD")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.1)

                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                            Text(text)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("Synced")
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.2, green: 0.82, blue: 0.35).opacity(0.15))
                                .foregroundStyle(Color(red: 0.2, green: 0.82, blue: 0.35))
                                .clipShape(Capsule())
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                }

                Divider()

                // Footer Actions
                HStack {
                    Button(action: {
                        PairingWindowController.shared.showPairingWindow()
                    }) {
                        Label("Pair Device", systemImage: "qrcode")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button(action: {
                        NSApp.terminate(nil)
                    }) {
                        Text("Quit Corda")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 320)
    }

    private func handleDroppedItems(_ providers: [NSItemProvider]) {
        guard let peer = server.connectedPeers.first(where: { $0.isTrusted }) ?? server.connectedPeers.first else {
            DispatchQueue.main.async {
                self.droppedFilesSummary = "Connect Android device first."
            }
            return
        }

        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                self.droppedFilesSummary = "Sending \(urls.count) item(s) to \(peer.name)..."
                FileStreamingManager.shared.sendFiles(urls: urls, to: peer)
            }
        }
    }

    private func selectAndSendFiles() {
        guard let peer = server.connectedPeers.first(where: { $0.isTrusted }) ?? server.connectedPeers.first else {
            DispatchQueue.main.async {
                self.droppedFilesSummary = "Connect Android device first."
            }
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Send to \(peer.name)"
        panel.message = "Choose files or folders to send to Android"

        if panel.runModal() == .OK {
            let urls = panel.urls
            if !urls.isEmpty {
                self.droppedFilesSummary = "Sending \(urls.count) item(s) to \(peer.name)..."
                FileStreamingManager.shared.sendFiles(urls: urls, to: peer)
            }
        }
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

/// Clean Minimalist Transfer Card
struct ActiveTransferCardView: View {
    let transfer: ActiveTransferProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: transfer.direction == "outgoing" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.currentFileName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(transfer.isCompleted ? "Transfer Complete ✨" : "File \(transfer.currentFileIndex + 1) of \(transfer.totalFiles) • \(String(format: "%.1f", transfer.speedMBs)) MB/s")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(transfer.progressPercent)%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
            }

            // Clean Solid Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color(red: 0.04, green: 0.52, blue: 1.0))
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(transfer.progressFraction))), height: 4)
                        .animation(.linear(duration: 0.2), value: transfer.progressFraction)
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

/// Clean Discovered Device Row
struct DeviceRowView: View {
    let device: DiscoveredDevice

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(device.isTrusted ? Color(red: 0.2, green: 0.82, blue: 0.35) : Color.orange)
                .frame(width: 8, height: 8)

            Image(systemName: "phone.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                Text(device.isTrusted ? "Trusted • Tap to Connect" : "Discovered • Tap to Pair")
                    .font(.system(size: 9))
                    .foregroundStyle(device.isTrusted ? Color.secondary : Color.orange)
            }

            Spacer()

            if !device.isTrusted {
                Button("Pair") {
                    PairingWindowController.shared.showPairingWindow()
                }
                .font(.system(size: 10, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

/// Clean Connected Peer Row
struct ConnectedPeerRowView: View {
    @ObservedObject var peer: ConnectedPeer

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(peer.isTrusted ? Color(red: 0.2, green: 0.82, blue: 0.35) : Color.orange)
                .frame(width: 8, height: 8)

            Image(systemName: "phone.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

            VStack(alignment: .leading, spacing: 1) {
                Text(peer.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(peer.isTrusted ? "Connected • Clipboard Sync Active" : "Connecting...")
                    .font(.system(size: 9))
                    .foregroundStyle(peer.isTrusted ? Color.secondary : Color.orange)
            }

            Spacer()

            if peer.isTrusted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.2, green: 0.82, blue: 0.35))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

/// Clean Sonoma Settings View for download folder & auto-accept
struct MacSettingsView: View {
    @ObservedObject private var fileStreaming = FileStreamingManager.shared
    var onClose: () -> Void
    @AppStorage("auto_accept_files") private var autoAcceptFiles: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Settings & Storage", systemImage: "gearshape.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Download Directory Card
            VStack(alignment: .leading, spacing: 8) {
                Text("DOWNLOAD LOCATION")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.1)

                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                    Text(fileStreaming.defaultDownloadsFolder.path)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )

                HStack(spacing: 6) {
                    Button(action: selectNewFolder) {
                        Label("Change...", systemImage: "folder.badge.gearshape")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: openInFinder) {
                        Label("Show in Finder", systemImage: "arrow.up.forward.square")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if UserDefaults.standard.string(forKey: "custom_download_path") != nil {
                        Button(action: resetFolder) {
                            Text("Reset")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Auto-Accept Toggle
            Toggle(isOn: $autoAcceptFiles) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Accept Files")
                        .font(.system(size: 11, weight: .medium))
                    Text("Automatically save received files from paired Android")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            // Protocol & Security Info
            VStack(alignment: .leading, spacing: 6) {
                Text("SECURITY & PRIVACY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.1)

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.2, green: 0.82, blue: 0.35))
                    Text("Direct Private Connection • End-to-End Encrypted")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "wifi")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                    Text("Local Wi-Fi Network • Zero Cloud Relay")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func selectNewFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose destination folder for files received from Android"

        if panel.runModal() == .OK, let selectedURL = panel.url {
            fileStreaming.setCustomDownloadsFolder(selectedURL)
        }
    }

    private func openInFinder() {
        NSWorkspace.shared.open(fileStreaming.defaultDownloadsFolder)
    }

    private func resetFolder() {
        fileStreaming.resetDownloadsFolder()
    }
}
