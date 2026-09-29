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

        // Start listening for high-speed file streams on Port 54322
        FileStreamingManager.shared.startListening()
    }

    func applicationWillTerminate(_ notification: Notification) {
        BonjourDiscoveryManager.shared.stopAdvertising()
        BonjourDiscoveryManager.shared.stopBrowsing()
        MacClipboardObserver.shared.stopObserving()
        FileStreamingManager.shared.stopListening()
    }
}

struct MenuBarStatusIconView: View {
    @ObservedObject private var discovery = BonjourDiscoveryManager.shared
    @ObservedObject private var server = ControlSessionServer.shared

    var body: some View {
        let isConnected = server.connectedPeers.contains(where: { $0.isTrusted })

        HStack(spacing: 3) {
            if let img = loadMenuBarIcon() {
                Image(nsImage: img)
                    .renderingMode(.template)
            } else {
                Image(systemName: isConnected ? "link.badge.plus" : "link")
                    .renderingMode(.template)
            }

            if isConnected {
                Circle()
                    .fill(Color(red: 0.0, green: 0.82, blue: 0.83))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func loadMenuBarIcon() -> NSImage? {
        if let mainUrl = Bundle.main.url(forResource: "menubar_icon", withExtension: "png"),
           let img = NSImage(contentsOf: mainUrl) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "menubar_icon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        #endif
        if let resPath = Bundle.main.resourcePath {
            let directPath = (resPath as NSString).appendingPathComponent("menubar_icon.png")
            if FileManager.default.fileExists(atPath: directPath),
               let img = NSImage(contentsOfFile: directPath) {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = true
                return img
            }
        }
        let paths = [
            "macos/CordaMac/Resources/menubar_icon.png",
            "assets/corda_logo_icon.png",
            "../assets/corda_logo_icon.png"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = true
                return img
            }
        }
        return nil
    }
}
