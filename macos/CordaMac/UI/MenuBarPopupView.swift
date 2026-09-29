import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The primary Sonoma Luminous Aqua popover displayed when clicking Corda in the macOS Menu Bar.
public struct MenuBarPopupView: View {
    @ObservedObject private var discovery = BonjourDiscoveryManager.shared
    @ObservedObject private var clipboard = MacClipboardObserver.shared

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

                    if discovery.discoveredDevices.isEmpty {
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
                        ForEach(discovery.discoveredDevices) { device in
                            DeviceRowView(device: device)
                        }
                    }
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
        var count = 0
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    count += 1
                    DispatchQueue.main.async {
                        self.droppedFilesSummary = "\(count) file(s) queued: \(url.lastPathComponent)"
                    }
                }
            }
        }
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

