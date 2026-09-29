import AppKit
import CryptoKit
import Combine

/// Observer for macOS NSPasteboard that detects user copy events in real-time,
/// filters out passwords, and prevents echo loops when writing synced text.
public final class MacClipboardObserver: ObservableObject {
    public static let shared = MacClipboardObserver()

    @Published public private(set) var lastCopiedText: String?
    @Published public private(set) var lastChangeTimestamp: Date?

    private var changeCount: Int
    private var timer: Timer?
    private var recentHashes: Set<String> = []
    private let queue = DispatchQueue(label: "com.corda.mac.clipboard.observer", qos: .utility)

    /// Callback invoked when clean, non-sensitive clipboard content is copied: (text, sha256Hex)
    public var onClipboardChanged: ((String, String) -> Void)?

    private init() {
        self.changeCount = NSPasteboard.general.changeCount
    }

    /// Start observing the system clipboard every 400ms.
    public func startObserving() {
        guard timer == nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.changeCount = NSPasteboard.general.changeCount
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                self?.checkForChanges()
            }
        }
    }

    /// Stop observing.
    public func stopObserving() {
        timer?.invalidate()
        timer = nil
    }

    /// Write text received from a remote Android device into NSPasteboard
    /// while registering its hash to prevent echoing back.
    public func writeRemoteText(_ text: String) {
        let hash = computeHash(for: text)
        recentHashes.insert(hash)

        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            self.changeCount = pasteboard.changeCount
            self.lastCopiedText = text
            self.lastChangeTimestamp = Date()
        }
    }

    private func checkForChanges() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != changeCount else { return }
        changeCount = currentCount

        // Check if clipboard is tagged as sensitive by a password manager
        if SensitiveDataFilter.isCurrentPasteboardSensitive() {
            #if DEBUG
            print("[Corda Clipboard] Sensitive data detected from Password Manager. Ignoring.")
            #endif
            return
        }

        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }

        let hash = computeHash(for: text)

        // Prevent echo loop if this was recently written by Corda from remote
        if recentHashes.contains(hash) {
            recentHashes.remove(hash)
            return
        }

        DispatchQueue.main.async {
            self.lastCopiedText = text
            self.lastChangeTimestamp = Date()
        }

        onClipboardChanged?(text, hash)
    }

    private func computeHash(for text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
