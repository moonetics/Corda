import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The primary Sonoma Luminous Aqua popover displayed when clicking Corda in the macOS Menu Bar.
public struct MenuBarPopupView: View {
    @ObservedObject private var discovery = BonjourDiscoveryManager.shared
    @ObservedObject private var clipboard = MacClipboardObserver.shared
    @ObservedObject private var server = ControlSessionServer.shared
    @ObservedObject private var fileStreaming = FileStreamingManager.shared

    @State private var isDropTargeted: Bool = false
    @State private var droppedFilesSummary: String? = nil

    public init() {}

    public var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)

            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.04, green: 0.52, blue: 1.0),   // Apple Blue #0A84FF
                                    Color(red: 0.0, green: 0.82, blue: 0.83)    // Sonoma Cyan #00D2D3
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Corda")
                            .font(.system(size: 15, weight: .bold))
                        Text("The invisible cord between your Mac and Android")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: {
                        PairingWindowController.shared.showPairingWindow()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                    }
                    .buttonStyle(.plain)
                    .help("Pair New Device")
                }

                Divider()

                // Connected & Nearby Devices Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("DEVICES ON LOCAL WI-FI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    if discovery.discoveredDevices.isEmpty && server.connectedPeers.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Searching on local network...")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Make sure Corda is open on your Android phone")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
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
                }

                // Active File Transfer Progress Card
                if let transfer = fileStreaming.activeTransfer {
                    ActiveTransferCardView(transfer: transfer)
                }

                // File DropZone Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("DROP FILES TO SEND")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isDropTargeted
                                    ? Color(red: 0.0, green: 0.82, blue: 0.83)
                                    : Color.primary.opacity(0.12),
                                style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isDropTargeted ? Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.08) : Color.primary.opacity(0.02))
                            )

                        VStack(spacing: 6) {
                            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "arrow.up.doc.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(
                                    isDropTargeted
                                        ? Color(red: 0.0, green: 0.82, blue: 0.83)
                                        : Color.secondary
                                )

                            Text(droppedFilesSummary ?? (isDropTargeted ? "Drop files now" : "Drag & drop files here"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(droppedFilesSummary != nil ? .primary : .secondary)
                        }
                        .padding(.vertical, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        handleDroppedItems(providers)
                        return true
                    }
                }

                // Live Clipboard Status Card
                if let text = clipboard.lastCopiedText {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                        Text(text)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text("Synced")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                }

                Divider()

                // Footer
                HStack {
                    Button(action: {
                        PairingWindowController.shared.showPairingWindow()
                    }) {
                        Label("Pair Device", systemImage: "qrcode")
                            .font(.system(size: 11))
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
            .padding(16)
        }
        .frame(width: 320)
    }

    private func handleDroppedItems(_ providers: [NSItemProvider]) {
        guard let peer = server.connectedPeers.first(where: { $0.isTrusted }) ?? server.connectedPeers.first else {
            DispatchQueue.main.async {
                self.droppedFilesSummary = "Hubungkan perangkat Android terlebih dahulu."
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
                self.droppedFilesSummary = "Mengirim \(urls.count) file ke \(peer.name)..."
                FileStreamingManager.shared.sendFiles(urls: urls, to: peer)
            }
        }
    }
}

/// Sonoma Aqua styled live transfer card.
struct ActiveTransferCardView: View {
    let transfer: ActiveTransferProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: transfer.direction == "outgoing" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.52, blue: 1.0),
                                Color(red: 0.0, green: 0.82, blue: 0.83)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.currentFileName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(transfer.isCompleted ? "Transfer Selesai ✨" : "Berkas \(transfer.currentFileIndex + 1) dari \(transfer.totalFiles) • \(String(format: "%.1f", transfer.speedMBs)) MB/s")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(transfer.progressPercent)%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.04, green: 0.52, blue: 1.0),
                                    Color(red: 0.0, green: 0.82, blue: 0.83)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(transfer.progressFraction))), height: 5)
                        .animation(.linear(duration: 0.2), value: transfer.progressFraction)
                }
            }
            .frame(height: 5)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(red: 0.0, green: 0.82, blue: 0.83).opacity(0.3), lineWidth: 1)
        )
    }
}

struct DeviceRowView: View {
    let device: DiscoveredDevice

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(device.isTrusted ? Color(red: 0.2, green: 0.82, blue: 0.35) : Color(red: 1.0, green: 0.62, blue: 0.04))
                .frame(width: 8, height: 8)

            Image(systemName: "phone.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                Text(device.isTrusted ? "Trusted & Connected" : "New Device • Tap to Pair")
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
                .fill(Color.primary.opacity(0.04))
        )
    }
}

struct ConnectedPeerRowView: View {
    @ObservedObject var peer: ConnectedPeer

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(peer.isTrusted ? Color(red: 0.2, green: 0.82, blue: 0.35) : Color(red: 1.0, green: 0.62, blue: 0.04))
                .frame(width: 8, height: 8)

            Image(systemName: "phone.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

            VStack(alignment: .leading, spacing: 1) {
                Text(peer.name)
                    .font(.system(size: 12, weight: .semibold))
                Text(peer.isTrusted ? "Connected • Clipboard Sync Active ⚡" : "Connecting...")
                    .font(.system(size: 9))
                    .foregroundStyle(peer.isTrusted ? Color.secondary : Color.orange)
            }

            Spacer()

            if peer.isTrusted {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.2, green: 0.82, blue: 0.35))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.06))
        )
    }
}

