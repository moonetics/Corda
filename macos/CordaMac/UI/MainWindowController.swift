import AppKit
import SwiftUI

/// Defines the 5 primary functional tabs of the Corda macOS Windowed Application.
public enum AppTab: String, CaseIterable, Identifiable {
    case devices = "devices"
    case transfers = "transfers"
    case notifications = "notifications"
    case clipboard = "clipboard"
    case settings = "settings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .devices: return "Devices"
        case .transfers: return "Transfers"
        case .notifications: return "Notifications"
        case .clipboard: return "Clipboard"
        case .settings: return "Settings"
        }
    }

    public var subtitle: String {
        switch self {
        case .devices: return "Paired & Nearby Companions"
        case .transfers: return "File Streaming & History"
        case .notifications: return "Mirrored Phone Alerts"
        case .clipboard: return "Universal Copy & Paste"
        case .settings: return "Preferences & Storage"
        }
    }

    public var iconName: String {
        switch self {
        case .devices: return "iphone.and.arrow.forward"
        case .transfers: return "arrow.up.arrow.down.circle"
        case .notifications: return "bell.badge"
        case .clipboard: return "doc.on.clipboard"
        case .settings: return "gearshape"
        }
    }
}

/// Singleton window controller managing the dedicated Sonoma Windowed Application.
/// Implements Dynamic Hybrid Mode: icon appears in Dock when open, and hides when closed.
public final class MainWindowController: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = MainWindowController()

    private var mainWindow: NSWindow?
    @Published public var selectedTab: AppTab = .devices

    private override init() {
        super.init()
    }

    /// Present or bring the main window to front on the requested tab.
    public func showWindow(tab: AppTab = .devices) {
        self.selectedTab = tab

        if let window = mainWindow {
            // Restore window if minimized or ordered out
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window
        let contentRect = NSRect(x: 0, y: 0, width: 840, height: 540)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Corda"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 740, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Host the SwiftUI NavigationSplitView
        let rootView = SonomaMainWindowView()
        window.contentView = NSHostingView(rootView: rootView)

        self.mainWindow = window

        // Dynamic Hybrid: show in Dock while window is active
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closeWindow() {
        mainWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Prevent application shutdown. Order out window and hide from Dock.
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    public func windowWillMiniaturize(_ notification: Notification) {
        // Keep in dock when minimized
    }
}
