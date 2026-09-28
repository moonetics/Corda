import SwiftUI
import AppKit

@main
struct CordaMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
        } label: {
            Image(systemName: "link")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Guarantee no dock icon appears (accessory agent policy)
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Sonoma Aqua branding
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
            }
            .padding(.bottom, 2)

            Divider()

            // Status Card
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(red: 0.2, green: 0.82, blue: 0.35)) // Apple Mint Green #34C759
                    .frame(width: 8, height: 8)
                Text("Service Ready (Idle)")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("v1.0.0")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            // Info note
            Text("Phase 0 Scaffolding Complete. Protocols and background socket engine will be connected in next phases.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Footer action
            HStack {
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Text("Quit Corda")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
