import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Main Sonoma Windowed Application root view with a translucent sidebar and 5 functional tabs.
public struct SonomaMainWindowView: View {
    @ObservedObject private var controller = MainWindowController.shared
    @ObservedObject private var discovery = BonjourDiscoveryManager.shared
    @ObservedObject private var server = ControlSessionServer.shared
    @ObservedObject private var fileStreaming = FileStreamingManager.shared
    public init() {}

    public var body: some View {
        NavigationSplitView {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                // Header Branding
                HStack(spacing: 10) {
                    if let img = loadAppLogo() {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("Corda")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.primary)

                            Text("v1.3")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }

                        Text("Apple Continuity for Android")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()
                    .padding(.horizontal, 12)

                // Navigation Items
                List(AppTab.allCases, id: \.self, selection: $controller.selectedTab) { tab in
                    HStack(spacing: 10) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 14))
                            .frame(width: 20)
                            .foregroundStyle(controller.selectedTab == tab ? Color(red: 0.04, green: 0.52, blue: 1.0) : .secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(tab.title)
                                .font(.system(size: 12, weight: controller.selectedTab == tab ? .semibold : .medium))
                                .foregroundStyle(controller.selectedTab == tab ? .primary : .secondary)

                            Text(tab.subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary.opacity(0.8))
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .tag(tab)
                }
                .listStyle(.sidebar)

                Spacer()

                // Sidebar Footer: Disk Capacity & Security
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 12)

                    // Storage widget
                    HStack(spacing: 8) {
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Downloads Storage")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text(getDiskCapacityString())
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.primary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    // Security badge
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))

                        Text("End-to-End Encrypted • Local Wi-Fi")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
        } detail: {
            // MARK: - Detail Content Views
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()

                switch controller.selectedTab {
                case .devices:
                    DevicesTabView()
                case .transfers:
                    TransfersTabView()
                case .notifications:
                    NotificationsTabView()
                case .clipboard:
                    ClipboardTabView()
                case .settings:
                    SettingsTabView()
                }
            }
            .frame(minWidth: 500, minHeight: 480)
        }
    }

    private func getDiskCapacityString() -> String {
        let url = fileStreaming.defaultDownloadsFolder
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let freeBytes = values.volumeAvailableCapacityForImportantUsage,
           let totalBytes = values.volumeTotalCapacity {
            let freeGB = Double(freeBytes) / 1_073_741_824.0
            let totalGB = Double(totalBytes) / 1_073_741_824.0
            let usedGB = max(0, totalGB - freeGB)
            return String(format: "%.1f GB Used • %.1f GB Free", usedGB, freeGB)
        }
        return "Available on Macintosh HD"
    }

    private func loadAppLogo() -> NSImage? {
        // 1. Check Bundle.main resources
        if let url = Bundle.main.url(forResource: "logo_corda", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let resPath = Bundle.main.resourcePath {
            let candidate = (resPath as NSString).appendingPathComponent("logo_corda.png")
            if FileManager.default.fileExists(atPath: candidate), let img = NSImage(contentsOfFile: candidate) {
                return img
            }
        }
        if let img = NSImage(named: "logo_corda") {
            return img
        }

        // 2. Direct paths for development or installed app
        let candidatePaths = [
            "/Applications/Corda.app/Contents/Resources/logo_corda.png",
            FileManager.default.currentDirectoryPath + "/macos/CordaMac/Resources/logo_corda.png",
            FileManager.default.currentDirectoryPath + "/assets/logo-corda.png",
            "/Users/percayajanji/Documents/Corda/macos/CordaMac/Resources/logo_corda.png",
            "/Users/percayajanji/Documents/Corda/assets/logo-corda.png"
        ]
        for p in candidatePaths {
            if FileManager.default.fileExists(atPath: p), let img = NSImage(contentsOfFile: p) {
                return img
            }
        }

        // 3. Fallback to NSApp application icon if available
        if let appIcon = NSApp.applicationIconImage {
            return appIcon
        }

        return nil
    }
}

// MARK: - 1. Devices Tab View
struct DevicesTabView: View {
    @ObservedObject private var discovery = BonjourDiscoveryManager.shared
    @ObservedObject private var server = ControlSessionServer.shared
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected & Nearby Devices")
                            .font(.system(size: 20, weight: .bold))
                        Text("Manage trusted companion devices and wireless pairing.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        PairingWindowController.shared.showPairingWindow()
                    }) {
                        Label("Pair New Device...", systemImage: "qrcode")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                // Active Connected Peer Card
                if let peer = server.connectedPeers.first(where: { $0.isTrusted }) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.12))
                                    .frame(width: 48, height: 48)

                                Image(systemName: "phone.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(peer.name)
                                        .font(.system(size: 16, weight: .bold))

                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                                            .frame(width: 6, height: 6)
                                        Text("Active")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.12))
                                    .clipShape(Capsule())
                                }

                                Text("Port 54321 (Control) & 54322 (Data Stream) • TLS 1.3")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Battery capsule
                            if let level = server.latestBatteryLevel {
                                HStack(spacing: 6) {
                                    Text("\(level)%")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))

                                    BatteryCapsuleIconView(
                                        level: level,
                                        isCharging: server.latestIsCharging
                                    )
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }

                        Divider()

                        HStack(spacing: 12) {
                            Button(action: selectAndSendFiles) {
                                Label("Send Files to Device...", systemImage: "arrow.up.doc.fill")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button(action: {
                                unpairDevice(fingerprint: peer.fingerprint)
                            }) {
                                Text("Unpair Device")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                } else {
                    // No companion connected
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)

                        Text("No Android Companion Connected")
                            .font(.system(size: 15, weight: .semibold))

                        Text("Make sure both your Mac and Android phone are on the same Wi-Fi network and Corda is running on both.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)

                        Button(action: {
                            PairingWindowController.shared.showPairingWindow()
                        }) {
                            Label("Pair New Companion via QR Code", systemImage: "qrcode")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                    )
                }

                // Discovered Nearby Devices Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("NEARBY DISCOVERED DEVICES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.1)

                    if discovery.discoveredDevices.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Searching for nearby Corda devices via Bonjour mDNS...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                    } else {
                        VStack(spacing: 8) {
                            ForEach(discovery.discoveredDevices) { dev in
                                let isConnected = server.connectedPeers.contains {
                                    (!dev.fingerprint.isEmpty && $0.fingerprint.caseInsensitiveCompare(dev.fingerprint) == .orderedSame) ||
                                    $0.name == dev.name
                                }

                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(isConnected ? Color(red: 0.20, green: 0.78, blue: 0.35) : (dev.isTrusted ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.orange))
                                        .frame(width: 8, height: 8)

                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(dev.name)
                                            .font(.system(size: 12, weight: .medium))
                                        Text("\(dev.platform.capitalized) • \(isConnected ? "Connected" : (dev.isTrusted ? "Trusted Companion" : "Ready to Pair"))")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if !dev.isTrusted {
                                        Button("Pair") {
                                            PairingWindowController.shared.showPairingWindow()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func selectAndSendFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Send via Corda"
        panel.message = "Choose files or folders to beam to Android"

        if panel.runModal() == .OK {
            FileStreamingManager.shared.sendFilesToConnectedPeer(urls: panel.urls)
        }
    }

    private func unpairDevice(fingerprint: String) {
        if let dev = KeychainManager.shared.getTrustedDevices().first(where: { $0.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame }) {
            try? KeychainManager.shared.removeTrustedDevice(id: dev.id)
        }
        server.disconnectPeer(fingerprint: fingerprint)
    }
}

// MARK: - 2. Transfers Tab View
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

struct TransfersTabView: View {
    @ObservedObject private var fileStreaming = FileStreamingManager.shared
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("File Transfers & Streaming")
                            .font(.system(size: 20, weight: .bold))
                        Text("High-speed direct socket streaming (Port 54322) with SHA-256 integrity.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: openDownloadsFolder) {
                        Label("Show Downloads", systemImage: "folder.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }

                // Active Transfer Card
                if let transfer = fileStreaming.activeTransfer {
                    ActiveTransferCardView(transfer: transfer)
                }

                // Generous Dropzone Beam Card
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color.primary.opacity(0.12),
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2.0 : 1.2, dash: [6, 4])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isDropTargeted ? Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.08) : Color.primary.opacity(0.03))
                        )

                    VStack(spacing: 8) {
                        Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                        Text(isDropTargeted ? "Release to Beam Files to Android" : "Drag files anywhere here to beam to Android")
                            .font(.system(size: 13, weight: .semibold))

                        Text("Or click anywhere in this box to select files from Finder")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectFiles()
                }
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                    return true
                }

                // Transfer History Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("DOWNLOAD DIRECTORY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.1)

                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Save Location")
                                .font(.system(size: 11, weight: .semibold))
                            Text(fileStreaming.defaultDownloadsFolder.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Change...") {
                            chooseNewFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                }
            }
            .padding(24)
        }
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Beam Files"
        if panel.runModal() == .OK {
            FileStreamingManager.shared.sendFilesToConnectedPeer(urls: panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let path = String(data: data, encoding: .utf8), let url = URL(string: path) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                FileStreamingManager.shared.sendFilesToConnectedPeer(urls: urls)
            }
        }
    }

    private func openDownloadsFolder() {
        NSWorkspace.shared.open(fileStreaming.defaultDownloadsFolder)
    }

    private func chooseNewFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let u = panel.url {
            fileStreaming.setCustomDownloadsFolder(u)
        }
    }
}

// MARK: - 3. Notifications Tab View
struct NotificationsTabView: View {
    @ObservedObject private var server = ControlSessionServer.shared
    @ObservedObject private var notifications = OtpNotificationManager.shared
    @AppStorage("notification_mirroring_enabled") private var mirroringEnabled: Bool = true
    @AppStorage("notification_hide_preview") private var hidePreview: Bool = false

    var body: some View {
        let connectedPhone = server.connectedPeers.first(where: { $0.isTrusted })
        let deviceName = connectedPhone?.name ?? "Android Device"
        let isConnected = connectedPhone != nil

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notification Mirroring")
                        .font(.system(size: 20, weight: .bold))
                    Text("Forward alerts and chat messages from your Android device directly to macOS Notification Center.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // System Notification Permission & Test Card
                if notifications.authorizationStatus == .authorized || notifications.authorizationStatus == .provisional {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Izin Notifikasi macOS Aktif")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text("Corda siap memunculkan banner alert ponsel di pojok kanan atas Mac Anda.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button(action: {
                                notifications.sendTestNotification()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "paperplane.fill")
                                    Text("Test Notifikasi")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("Pengaturan") {
                                notifications.openSystemNotificationSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.green.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                            )
                    )
                } else if notifications.authorizationStatus == .denied {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Izin Notifikasi macOS Dinonaktifkan")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text("Buka Pengaturan Sistem Mac > Pemberitahuan > Corda, lalu aktifkan 'Izinkan Pemberitahuan'.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button("Periksa Status") {
                                notifications.checkAuthorizationStatus()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("Buka Pengaturan") {
                                notifications.openSystemNotificationSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                    )
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uji Coba & Izin Notifikasi macOS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text("Kirim test alert untuk memastikan notifikasi banner muncul di pojok kanan atas Mac.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button(action: {
                                notifications.requestPermission()
                                notifications.sendTestNotification()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "paperplane.fill")
                                    Text("Test Notifikasi")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("Buka Pengaturan") {
                                notifications.openSystemNotificationSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.2), lineWidth: 1)
                            )
                    )
                }

                // Master & Mode Toggle Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mirror Phone Notifications")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Receive incoming alerts from WhatsApp, Telegram, Banking, and E-Commerce")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { server.isNotificationMasterEnabled },
                            set: { val in
                                server.isNotificationMasterEnabled = val
                                server.sendNotificationWhitelistUpdate(masterEnabled: val)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    if server.isNotificationMasterEnabled {
                        Divider()

                        // All Applications Mode Toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("All App Notification")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Apple Continuity")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.15))
                                        .clipShape(Capsule())
                                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                                }
                                Text("Forward notifications from all installed apps automatically (Apple Continuity)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { server.isAllAppsEnabled },
                                set: { val in
                                    server.isAllAppsEnabled = val
                                    server.sendNotificationWhitelistUpdate(allAppsEnabled: val)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

                        if server.isAllAppsEnabled {
                            HStack(spacing: 10) {
                                Image(systemName: "gearshape.2.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("All System Notification")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Internal OS alerts, charging status & system UI notifications (default off)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { server.isAllSystemEnabled },
                                    set: { val in
                                        server.isAllSystemEnabled = val
                                        server.sendNotificationWhitelistUpdate(allSystemEnabled: val)
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                            .padding(.leading, 8)
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hide Notification Preview (Privacy Mode)")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Masks message text as 'Pesan Baru Diterima' during presentations and screen sharing")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $hidePreview)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )

                // Source-Side Whitelist / Universal Information
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(server.isAllAppsEnabled ? "UNIVERSAL NOTIFICATION FORWARDING" : "SOURCE-SIDE SMART FILTER (ANDROID)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.1)

                        Spacer()

                        if isConnected {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                                    .frame(width: 5, height: 5)
                                let statusText = server.isAllAppsEnabled
                                    ? "All Applications Active"
                                    : "\(server.whitelistedApps.filter { $0.isEnabled }.count) active"
                                Text("Synced from \(deviceName) • \(statusText)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Waiting for phone connection...")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        if server.isAllAppsEnabled {
                            // Universal Mode Active Card
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.12))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "globe")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("All Applications Mode Active")
                                        .font(.system(size: 13, weight: .semibold))

                                    Text("Incoming alerts from all apps on \(deviceName) are mirrored automatically. You can toggle off any app below to exclude/mute it.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.2), lineWidth: 1)
                                    )
                            )
                        } else {
                            Text("Notifications are filtered on your Android phone before transmission to preserve battery and local Wi-Fi bandwidth. Manage allowed apps on your phone or toggle them below.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        if server.whitelistedApps.isEmpty && !server.isAllAppsEnabled {
                            // Empty State
                            VStack(spacing: 12) {
                                Image(systemName: "bell.badge.slash")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary.opacity(0.6))

                                Text("Belum Ada Aplikasi di-Whitelist")
                                    .font(.system(size: 13, weight: .semibold))

                                Text("Buka aplikasi Corda di ponsel Android Anda > Tab Pengaturan > Ketuk '+ Tambah Aplikasi' untuk memilih aplikasi yang boleh meneruskan notifikasi ke Mac, atau aktifkan 'All Applications Mode' di atas.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 420)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(Color.primary.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(server.whitelistedApps) { app in
                                    let isBlacklisted = server.isAllAppsEnabled && server.blacklistedApps.contains(app.packageName)
                                    let isAppActive = server.isAllAppsEnabled ? !isBlacklisted : app.isEnabled

                                    HStack(spacing: 10) {
                                        Image(systemName: isAppActive ? "checkmark.seal.fill" : "pause.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(isAppActive ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.secondary)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(app.appName)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            Text(app.packageName)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Button(action: {
                                            if server.isAllAppsEnabled {
                                                server.sendNotificationWhitelistUpdate(
                                                    packageToBlacklist: app.packageName,
                                                    packageBlacklisted: !isBlacklisted
                                                )
                                            } else {
                                                server.sendNotificationWhitelistUpdate(
                                                    packageToToggle: app.packageName,
                                                    packageEnabled: !app.isEnabled
                                                )
                                            }
                                        }) {
                                            Text(isAppActive ? "Active" : (server.isAllAppsEnabled ? "Muted" : "Paused"))
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(isAppActive ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    (isAppActive ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.secondary).opacity(0.12)
                                                )
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.primary.opacity(0.03))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                }
            }
            .padding(24)
        }
        .onAppear {
            notifications.checkAuthorizationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            notifications.checkAuthorizationStatus()
        }
    }
}

// MARK: - 4. Clipboard Tab View
struct ClipboardTabView: View {
    @ObservedObject private var clipboard = MacClipboardObserver.shared
    @State private var copiedRecently: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 2) {
                    Text("Universal Clipboard")
                        .font(.system(size: 20, weight: .bold))
                    Text("Seamless two-way copy & paste between Mac and Android over local TLS 1.3 socket.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // Active Status Card
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Universal Clipboard Active")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Copying text or images on Mac instantly mirrors to Android, and vice versa.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )

                // Recent Clipboard Item Card
                VStack(alignment: .leading, spacing: 10) {
                    Text("MOST RECENT CLIPBOARD ITEM")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.1)

                    if let text = clipboard.lastCopiedText {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(6)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            HStack(spacing: 12) {
                                Text("\(text.count) characters")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                    copiedRecently = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        copiedRecently = false
                                    }
                                }) {
                                    Label(copiedRecently ? "Copied!" : "Copy Again", systemImage: copiedRecently ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    } else {
                        Text("No recent clipboard item synced yet. Copy any text on your Mac or Android phone.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - 5. Settings Tab View
struct SettingsTabView: View {
    @ObservedObject private var fileStreaming = FileStreamingManager.shared
    @AppStorage("auto_accept_files") private var autoAcceptFiles: Bool = true
    @AppStorage("show_battery_in_menubar") private var showBatteryInMenuBar: Bool = true
    @AppStorage("otp_auto_copy") private var otpAutoCopy: Bool = false
    @AppStorage("screen_edge_dropzone_enabled") private var screenEdgeDropzoneEnabled: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings & Continuity")
                        .font(.system(size: 20, weight: .bold))
                    Text("Customize Apple Continuity behavior, save directories, and system integration.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // Continuity Preferences Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("CONTINUITY & PRODUCTIVITY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.1)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Accept Incoming Files")
                                .font(.system(size: 13, weight: .medium))
                            Text("Save received files from paired Android directly to Downloads folder")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $autoAcceptFiles)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live Battery in Menu Bar")
                                .font(.system(size: 13, weight: .medium))
                            Text("Display Android percentage and monochrome status on Mac status bar")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $showBatteryInMenuBar)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Copy Smart OTP Codes")
                                .font(.system(size: 13, weight: .medium))
                            Text("Automatically copy incoming verification codes to clipboard for 60 seconds")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $otpAutoCopy)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screen Edge Dropzone")
                                .font(.system(size: 13, weight: .medium))
                            Text("Instant 0.15s slide-out drawer when dragging files within 24px of the right screen edge")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $screenEdgeDropzoneEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: screenEdgeDropzoneEnabled) {
                                ScreenEdgeDropzoneController.shared.reloadPreferences()
                            }
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )

                // Save Directory Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("DOWNLOAD DESTINATION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.1)

                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                        Text(fileStreaming.defaultDownloadsFolder.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Change...") {
                            chooseNewFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Show in Finder") {
                            NSWorkspace.shared.open(fileStreaming.defaultDownloadsFolder)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .padding(24)
        }
    }

    private func chooseNewFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let u = panel.url {
            fileStreaming.setCustomDownloadsFolder(u)
        }
    }
}
