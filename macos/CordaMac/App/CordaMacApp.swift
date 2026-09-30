import SwiftUI
import AppKit

@main
struct CordaMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopupView()
        } label: {
            MenuBarStatusIconView()
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce accessory activation policy (no dock icon, pure status bar agent)
        NSApp.setActivationPolicy(.accessory)

        // Initialize and start background Bonjour mDNS discovery
        BonjourDiscoveryManager.shared.startAdvertising()
        BonjourDiscoveryManager.shared.startBrowsing()

        // Start observing NSPasteboard changes with privacy filter
        MacClipboardObserver.shared.startObserving()
        MacClipboardObserver.shared.onClipboardChanged = { text, hash in
            #if DEBUG
            print("[Corda Clipboard Event] User copied \(text.count) characters. SHA256: \(hash.prefix(8))...")
            #endif
            ControlSessionServer.shared.broadcastClipboard(text: text, hash: hash)
        }
        MacClipboardObserver.shared.onClipboardFileChanged = { url, mimeType, sizeBytes, sha256 in
            #if DEBUG
            print("[Corda Clipboard File Event] User copied file: \(url.lastPathComponent) (\(sizeBytes) bytes, \(mimeType))")
            #endif
            FileStreamingManager.shared.sendClipboardFile(url: url, mimeType: mimeType, sizeBytes: sizeBytes, sha256: sha256)
        }

        // Start listening for high-speed file streams on Port 54322
        FileStreamingManager.shared.startListening()

        // Initialize Notification Manager & Screen Edge Dropzone
        OtpNotificationManager.shared.setup()
        ScreenEdgeDropzoneController.shared.start()

        // Global keyboard shortcut monitor for Cmd+, (Settings) and Cmd+O (Open Corda)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "," {
                    MainWindowController.shared.showWindow(tab: .settings)
                    return nil
                } else if event.charactersIgnoringModifiers?.lowercased() == "o" {
                    MainWindowController.shared.showWindow(tab: .devices)
                    return nil
                }
            }
            return event
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.showWindow(tab: .devices)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        BonjourDiscoveryManager.shared.stopAdvertising()
        BonjourDiscoveryManager.shared.stopBrowsing()
        MacClipboardObserver.shared.stopObserving()
        FileStreamingManager.shared.stopListening()
    }
}

/// Pure monochrome horizontal battery capsule icon matching macOS native styling.
struct BatteryCapsuleIconView: View {
    let level: Int
    let isCharging: Bool

    var body: some View {
        HStack(spacing: 1) {
            // Main battery capsule container
            ZStack(alignment: .leading) {
                // Outer shell
                RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1)
                    .frame(width: 17, height: 9.5)

                // Fill level bar
                let clampedLevel = CGFloat(max(0, min(100, level))) / 100.0
                let fillWidth = max(0, (17 - 3.2) * clampedLevel)
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(Color.primary)
                    .frame(width: fillWidth, height: 6.5)
                    .padding(.leading, 1.6)

                // Monochrome lightning bolt when charging
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(clampedLevel > 0.45 ? Color(NSColor.windowBackgroundColor) : Color.primary)
                        .frame(width: 17, height: 9.5, alignment: .center)
                }
            }

            // Right terminal bump / anode
            RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                .fill(Color.primary.opacity(0.85))
                .frame(width: 1.5, height: 3.8)
        }
        .frame(height: 12)
    }
}

struct MenuBarStatusIconView: View {
    @ObservedObject private var discovery = BonjourDiscoveryManager.shared
    @ObservedObject private var server = ControlSessionServer.shared
    @AppStorage("show_battery_in_menubar") private var showBattery: Bool = true

    var body: some View {
        let isConnected = server.connectedPeers.contains(where: { $0.isTrusted })

        HStack(spacing: 4) {
            if let img = loadMenuBarIcon() {
                Image(nsImage: img)
                    .renderingMode(.template)
            } else {
                Image(systemName: isConnected ? "link.badge.plus" : "link")
                    .renderingMode(.template)
            }

            if isConnected {
                if showBattery, let level = server.latestBatteryLevel {
                    HStack(spacing: 2) {
                        if server.latestIsCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Color.primary)
                        }
                        Text("\(level)%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary)
                    }
                } else {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                        .frame(width: 4, height: 4)
                }
            }
        }
    }

    private func loadMenuBarIcon() -> NSImage? {
        let targetSize = NSSize(width: 18, height: 18)

        var urlsToTry: [URL] = []
        if let u = Bundle.main.url(forResource: "menubar_icon@2x", withExtension: "png") { urlsToTry.append(u) }
        if let u = Bundle.main.url(forResource: "menubar_icon", withExtension: "png") { urlsToTry.append(u) }

        #if SWIFT_PACKAGE
        if let u = Bundle.module.url(forResource: "menubar_icon@2x", withExtension: "png") { urlsToTry.append(u) }
        if let u = Bundle.module.url(forResource: "menubar_icon", withExtension: "png") { urlsToTry.append(u) }
        #endif

        if let resPath = Bundle.main.resourcePath {
            let p2x = (resPath as NSString).appendingPathComponent("menubar_icon@2x.png")
            let p1x = (resPath as NSString).appendingPathComponent("menubar_icon.png")
            urlsToTry.append(URL(fileURLWithPath: p2x))
            urlsToTry.append(URL(fileURLWithPath: p1x))
        }

        urlsToTry.append(URL(fileURLWithPath: "macos/CordaMac/Resources/menubar_icon@2x.png"))
        urlsToTry.append(URL(fileURLWithPath: "macos/CordaMac/Resources/menubar_icon.png"))
        urlsToTry.append(URL(fileURLWithPath: "assets/logo-corda.png"))

        for url in urlsToTry {
            if FileManager.default.fileExists(atPath: url.path),
               let img = NSImage(contentsOf: url) {
                img.size = targetSize
                img.isTemplate = true
                return img
            }
        }
        return nil
    }
}
