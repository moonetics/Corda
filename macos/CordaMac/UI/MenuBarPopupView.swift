import SwiftUI
import AppKit

/// Sleek & compact macOS menu bar popover (ala Purge) styled with Apple Continuity English aesthetics.
/// Provides instant status and direct quick actions without crowded nested forms.
public struct MenuBarPopupView: View {
    @ObservedObject private var server = ControlSessionServer.shared
    @ObservedObject private var discovery = BonjourDiscoveryManager.shared
    @ObservedObject private var fileStreaming = FileStreamingManager.shared

    public init() {}

    public var body: some View {
        let trustedPeer = server.connectedPeers.first(where: { $0.isTrusted })
        let isConnected = trustedPeer != nil

        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Companion Status Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isConnected ? Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.15) : Color.primary.opacity(0.08))
                        .frame(width: 32, height: 32)

                    Image(systemName: isConnected ? "phone.fill" : "wifi.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(isConnected ? Color(red: 0.20, green: 0.78, blue: 0.35) : .secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(trustedPeer?.name ?? (discovery.discoveredDevices.first?.name ?? "No Device Connected"))
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(isConnected ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.secondary)
                            .frame(width: 5, height: 5)

                        Text(isConnected ? "Connected" : "Searching...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Live Battery Capsule
                if isConnected, let level = server.latestBatteryLevel {
                    HStack(spacing: 4) {
                        Text("\(level)%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)

                        BatteryCapsuleIconView(
                            level: level,
                            isCharging: server.latestIsCharging
                        )
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            // Active Transfer Mini Banner (if transfer in progress or just completed)
            if let transfer = fileStreaming.activeTransfer {
                HStack(spacing: 8) {
                    if transfer.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                            .frame(width: 14, height: 14)
                    } else {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(transfer.currentFileName)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Text(transfer.isCompleted ? "100% • Selesai" : "\(transfer.progressPercent)% • \(String(format: "%.1f", transfer.speedMBs)) MB/s")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(6)
                .background(
                    (transfer.isCompleted ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color(red: 0.04, green: 0.52, blue: 1.0))
                        .opacity(0.12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Divider()

            // MARK: - Quick Action Buttons
            VStack(spacing: 3) {
                QuickActionButton(
                    title: "Open Corda...",
                    subtitle: "Full workspace & devices",
                    icon: "macwindow",
                    shortcut: "⌘O"
                ) {
                    MainWindowController.shared.showWindow(tab: .devices)
                }

                QuickActionButton(
                    title: "Send Files...",
                    subtitle: "Beam files to companion",
                    icon: "arrow.up.doc.fill",
                    shortcut: "⌘S"
                ) {
                    selectAndSendFiles()
                }

                QuickActionButton(
                    title: "Settings...",
                    subtitle: "Preferences & directory",
                    icon: "gearshape.fill",
                    shortcut: "⌘,"
                ) {
                    MainWindowController.shared.showWindow(tab: .settings)
                }
            }

            Divider()

            // MARK: - Footer: Quit
            HStack {
                Text("Corda Continuity v1.2")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Quit Corda") {
                    NSApp.terminate(nil)
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
        .padding(10)
        .frame(width: 260)
    }

    private func selectAndSendFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Beam Files"
        panel.message = "Choose files or folders to beam to Android"

        if panel.runModal() == .OK {
            FileStreamingManager.shared.sendFilesToConnectedPeer(urls: panel.urls)
        }
    }
}

/// Minimalist macOS Sonoma quick action row button.
struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(isHovered ? Color(red: 0.04, green: 0.52, blue: 1.0) : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(shortcut)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(isHovered ? 0.08 : 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
