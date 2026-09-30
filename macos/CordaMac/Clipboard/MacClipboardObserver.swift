import AppKit
import CryptoKit
import Combine

/// Observer for macOS NSPasteboard that detects user copy events in real-time,
/// filters out passwords, supports seamless files & images (<= 50MB),
/// and prevents echo loops when writing synced text and files.
public final class MacClipboardObserver: ObservableObject {
    public static let shared = MacClipboardObserver()

    public static let maxClipboardFileSize: Int64 = 52_428_800 // 50 MB

    @Published public private(set) var lastCopiedText: String?
    @Published public private(set) var lastChangeTimestamp: Date?

    private var changeCount: Int
    private var timer: Timer?
    private var recentHashes: Set<String> = []
    private let queue = DispatchQueue(label: "com.corda.mac.clipboard.observer", qos: .utility)

    /// Callback invoked when clean, non-sensitive text is copied: (text, sha256Hex)
    public var onClipboardChanged: ((String, String) -> Void)?

    /// Callback invoked when a file or image (<= 50MB) is copied: (localURL, mimeType, sizeBytes, sha256Hex)
    public var onClipboardFileChanged: ((URL, String, Int64, String) -> Void)?

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
        // Discard any synthetic file/folder preview labels
        if text.hasPrefix("[File: ") || text.hasPrefix("🖼️ ") || text.hasPrefix("📁 ") {
            #if DEBUG
            print("[Corda Clipboard] Discarding synthetic file label from remote text write: \(text)")
            #endif
            return
        }

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

    /// Write a received file or image into NSPasteboard as native file URL and NSImage
    /// so Finder pastes the file and chat/editor apps paste the actual file/image.
    public func writeRemoteFile(localURL: URL, mimeType: String, hash: String) {
        recentHashes.insert(hash.lowercased())

        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            var objectsToPaste: [NSPasteboardWriting] = [localURL as NSURL]
            let isImage = mimeType.starts(with: "image/") ||
                ["png", "jpg", "jpeg", "webp", "gif"].contains(localURL.pathExtension.lowercased())

            if isImage, let image = NSImage(contentsOf: localURL) {
                objectsToPaste.append(image)
            }
            pasteboard.writeObjects(objectsToPaste)

            if isImage, let imgData = try? Data(contentsOf: localURL) {
                pasteboard.setData(imgData, forType: .png)
            }

            self.changeCount = pasteboard.changeCount
            self.lastCopiedText = localURL.lastPathComponent
            self.lastChangeTimestamp = Date()
            NSSound(named: "Pop")?.play()
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

        let pasteboard = NSPasteboard.general

        // 1. Check for File URL copy in Finder
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first, firstURL.isFileURL {
            let path = firstURL.path
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                if isDir.boolValue {
                    // It's a directory/folder: preserve native pasteboard without falling back to plain text
                    #if DEBUG
                    print("[Corda Clipboard] Directory copy detected: \(firstURL.lastPathComponent). Skipping plain text fallback.")
                    #endif
                    return
                } else if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                          let fileSize = attrs[.size] as? Int64, fileSize > 0 && fileSize <= Self.maxClipboardFileSize {
                    let hash = computeFileHash(for: firstURL).lowercased()
                    if recentHashes.contains(hash) {
                        recentHashes.remove(hash)
                        return
                    }
                    let ext = firstURL.pathExtension.lowercased()
                    let mimeType = getMimeType(forExtension: ext)
                    DispatchQueue.main.async {
                        self.lastCopiedText = firstURL.lastPathComponent
                        self.lastChangeTimestamp = Date()
                    }
                    onClipboardFileChanged?(firstURL, mimeType, fileSize, hash)
                    return
                } else {
                    // File > 50MB: preserve native pasteboard without falling back to plain text
                    #if DEBUG
                    print("[Corda Clipboard] Large file copy detected (> 50MB). Skipping plain text fallback.")
                    #endif
                    return
                }
            }
        }

        // Extra safeguard: if pasteboard types explicitly declare file URLs, NEVER fall through to plain text
        if pasteboard.types?.contains(.fileURL) == true ||
           pasteboard.types?.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) == true {
            return
        }

        // 2. Check for Direct Image copy (Preview, Browser, Screenshot, etc.) (<= 50MB)
        if let imgData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let size = Int64(imgData.count)
            if size > 0 && size <= Self.maxClipboardFileSize {
                let hash = computeHash(for: imgData).lowercased()
                if recentHashes.contains(hash) {
                    recentHashes.remove(hash)
                    return
                }
                let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let tempFile = tempDir.appendingPathComponent("Corda_Clip_\(UUID().uuidString.prefix(8)).png")
                try? imgData.write(to: tempFile)
                DispatchQueue.main.async {
                    self.lastCopiedText = "Image (" + ByteCountFormatter.string(fromByteCount: size, countStyle: .file) + ")"
                    self.lastChangeTimestamp = Date()
                }
                onClipboardFileChanged?(tempFile, "image/png", size, hash)
                return
            }
        }

        // 3. Fallback to Plain Text
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return
        }

        let hash = computeHash(for: text).lowercased()

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
        return computeHash(for: data)
    }

    private func computeHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func computeFileHash(for url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 262144)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func getMimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "zip": return "application/zip"
        case "mp4": return "video/mp4"
        case "mp3": return "audio/mpeg"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }
}
