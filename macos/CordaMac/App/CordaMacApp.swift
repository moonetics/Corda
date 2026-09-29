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
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        BonjourDiscoveryManager.shared.stopAdvertising()
        BonjourDiscoveryManager.shared.stopBrowsing()
        MacClipboardObserver.shared.stopObserving()
    }
}

struct MenuBarStatusIconView: View {
    @ObservedObject private var discovery = BonjourDiscoveryManager.shared

    var body: some View {
        let hasTrusted = discovery.discoveredDevices.contains(where: { $0.isTrusted })
        let iconName = hasTrusted ? "link.badge.plus" : "link"
        Image(systemName: iconName)
            .renderingMode(.template)
    }
}
