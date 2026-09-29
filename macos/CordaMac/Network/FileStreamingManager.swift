import Foundation
import Network
import Combine
import CryptoKit
import AppKit

public struct TransferFileItem: Identifiable, Codable {
    public var id: String { name }
    public let name: String
    public let relativePath: String
    public let sizeBytes: Int64
    public let sha256: String

    public init(name: String, relativePath: String, sizeBytes: Int64, sha256: String) {
        self.name = name
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
    }
}

public struct ActiveTransferProgress: Identifiable {
    public let id: String
    public let direction: String // "incoming" or "outgoing"
    public let currentFileName: String
    public let totalFiles: Int
    public let currentFileIndex: Int
    public let totalBytes: Int64
    public let transferredBytes: Int64
    public let progressFraction: Double // 0.0 to 1.0
    public let speedMBs: Double
    public let isCompleted: Bool

    public var progressPercent: Int {
        Int((progressFraction * 100).clamped(to: 0...100))
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

/// High-Speed Binary Data Stream Manager running on Port 54322,
/// handling chunked 256KB streaming, dual SHA-256 verification, and Auto-Accept to Downloads/Corda.
public final class FileStreamingManager: ObservableObject {
    public static let shared = FileStreamingManager()

    public static let dataPort: UInt16 = 54322
    public static let chunkSize: Int = 262_144 // 256 KB

    private static let magicBytes: [UInt8] = [0x43, 0x4F, 0x52, 0x44] // "CORD"

    @Published public private(set) var activeTransfer: ActiveTransferProgress?
    @Published public private(set) var isListening: Bool = false

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.corda.mac.data.stream", qos: .userInitiated)

    // Receiving session state
    private var currentReceiveMetadata: [String: Any]?
    private var activeDataConnection: NWConnection?
    private var currentFileWriter: FileHandle?
    private var currentTempFileURL: URL?
    private var currentFileHasher = SHA256()
    private var currentFileIndex: Int = 0
    private var currentTransferTransferredBytes: Int64 = 0
    private var transferStartTime: Date = Date()

    // Outgoing transfer queue
    public struct PendingOutgoingTransfer {
        public let transferId: UUID
        public let manifest: [TransferFileItem]
        public let totalBytes: Int64
        public let fileURLs: [URL]
    }
    private var pendingOutgoingTransfers: [UUID: PendingOutgoingTransfer] = [:]

    private init() {}

    public var defaultDownloadsFolder: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let cordaFolder = downloads.appendingPathComponent("Corda", isDirectory: true)
        try? FileManager.default.createDirectory(at: cordaFolder, withIntermediateDirectories: true)
        return cordaFolder
    }

    // MARK: - Server Listener (Port 54322)

    public func startListening() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let nwListener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.dataPort)!)
            nwListener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isListening = true
                        #if DEBUG
                        print("[DataStream] Listening on port \(Self.dataPort) ready for binary file streams.")
                        #endif
                    case .failed(let error):
                        self?.isListening = false
                        #if DEBUG
                        print("[DataStream] Listener failed: \(error)")
                        #endif
                    case .cancelled:
                        self?.isListening = false
                    default:
                        break
                    }
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingDataConnection(connection)
            }

            self.listener = nwListener
            nwListener.start(queue: queue)
        } catch {
            #if DEBUG
            print("[DataStream] Failed to start data listener: \(error)")
            #endif
        }
    }

    public func stopListening() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    private func handleIncomingDataConnection(_ connection: NWConnection) {
        self.activeDataConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                #if DEBUG
                print("[DataStream] Data connection established with \(connection.endpoint)")
                #endif
                self?.readNextFrame(from: connection)
            case .failed(let error):
                #if DEBUG
                print("[DataStream] Data connection failed: \(error)")
                #endif
                self?.cleanupReceivingSession()
            case .cancelled:
                self?.cleanupReceivingSession()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // MARK: - Binary Frame Receiver (Android -> Mac)

    public func prepareIncomingTransfer(metadata: [String: Any]) {
        self.currentReceiveMetadata = metadata
        self.currentTransferTransferredBytes = 0
        self.currentFileIndex = 0
        self.transferStartTime = Date()

        let transferId = metadata["transfer_id"] as? String ?? UUID().uuidString
        let totalFiles = metadata["total_files"] as? Int ?? 1
        let totalBytes = metadata["total_bytes"] as? Int64 ?? 0
        let files = metadata["files"] as? [[String: Any]] ?? []
        let firstFileName = files.first?["name"] as? String ?? "Incoming File"

        DispatchQueue.main.async {
            self.activeTransfer = ActiveTransferProgress(
                id: transferId,
                direction: "incoming",
                currentFileName: firstFileName,
                totalFiles: totalFiles,
                currentFileIndex: 0,
                totalBytes: totalBytes,
                transferredBytes: 0,
                progressFraction: 0.0,
                speedMBs: 0.0,
                isCompleted: false
            )
        }
    }

    private func readNextFrame(from connection: NWConnection) {
        // Read 40-byte binary header
        connection.receive(minimumIncompleteLength: 40, maximumLength: 40) { [weak self] headerData, _, isComplete, error in
            guard let self = self, let header = headerData, header.count == 40, error == nil else {
                if isComplete { self?.cleanupReceivingSession() }
                return
            }

            // Verify Magic Bytes
            guard header[0] == Self.magicBytes[0] &&
                  header[1] == Self.magicBytes[1] &&
                  header[2] == Self.magicBytes[2] &&
                  header[3] == Self.magicBytes[3] else {
                #if DEBUG
                print("[DataStream] Invalid Magic Bytes in header. Aborting frame.")
                #endif
                return
            }

            let msgType = header[5]
            let payloadLen = header.subdata(in: 36..<40).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            if msgType == 0x01 { // CHUNK_DATA
                self.readChunkPayloadAndChecksum(from: connection, payloadLength: Int(payloadLen), header: header)
            } else if msgType == 0x02 { // FILE_COMPLETE
                self.handleFileCompleteFrame()
                self.readNextFrame(from: connection)
            } else if msgType == 0x03 { // TRANSFER_COMPLETE
                self.handleTransferComplete()
            } else if msgType == 0x04 { // READY_PULL
                let rawUUIDBytes = [UInt8](header.subdata(in: 8..<24))
                let uuid = UUID(uuid: (
                    rawUUIDBytes[0], rawUUIDBytes[1], rawUUIDBytes[2], rawUUIDBytes[3],
                    rawUUIDBytes[4], rawUUIDBytes[5], rawUUIDBytes[6], rawUUIDBytes[7],
                    rawUUIDBytes[8], rawUUIDBytes[9], rawUUIDBytes[10], rawUUIDBytes[11],
                    rawUUIDBytes[12], rawUUIDBytes[13], rawUUIDBytes[14], rawUUIDBytes[15]
                ))
                if let pending = self.pendingOutgoingTransfers.removeValue(forKey: uuid) {
                    self.streamOutgoingTransfer(pending, on: connection)
                }
            } else {
                self.readNextFrame(from: connection)
            }
        }
    }

    private func readChunkPayloadAndChecksum(from connection: NWConnection, payloadLength: Int, header: Data) {
        let totalExpected = payloadLength + 32 // payload + SHA256 checksum
        connection.receive(minimumIncompleteLength: totalExpected, maximumLength: totalExpected) { [weak self] chunkData, _, _, error in
            guard let self = self, let data = chunkData, data.count == totalExpected, error == nil else {
                return
            }

            let rawPayload = data.subdata(in: 0..<payloadLength)
            let receivedChecksum = data.subdata(in: payloadLength..<totalExpected)

            // Validate chunk SHA-256
            let calculatedHash = Data(SHA256.hash(data: rawPayload))
            guard calculatedHash == receivedChecksum else {
                #if DEBUG
                print("[DataStream] Chunk checksum mismatch! Corrupted chunk dropped.")
                #endif
                return
            }

            // Write chunk to temp file
            self.writeChunkToDisk(rawPayload)

            // Update progress
            self.currentTransferTransferredBytes += Int64(payloadLength)
            self.updateTransferProgress()

            // Ready for next frame
            self.readNextFrame(from: connection)
        }
    }

    private func writeChunkToDisk(_ data: Data) {
        if currentFileWriter == nil {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("corda_temp_\(UUID().uuidString).part")
            FileManager.default.createFile(atPath: tempFile.path, contents: nil)
            currentTempFileURL = tempFile
            currentFileWriter = try? FileHandle(forWritingTo: tempFile)
            currentFileHasher = SHA256()
        }

        currentFileWriter?.write(data)
        currentFileHasher.update(data: data)
    }

    private func handleFileCompleteFrame() {
        currentFileWriter?.closeFile()
        currentFileWriter = nil

        guard let tempURL = currentTempFileURL,
              let metadata = currentReceiveMetadata,
              let files = metadata["files"] as? [[String: Any]],
              currentFileIndex < files.count else {
            return
        }

        let fileMeta = files[currentFileIndex]
        let expectedSha256 = (fileMeta["sha256"] as? String ?? "").lowercased()
        let relativePath = fileMeta["relative_path"] as? String ?? (fileMeta["name"] as? String ?? "file")

        // Final whole-file SHA-256 verification
        let finalDigest = currentFileHasher.finalize()
        let finalHex = finalDigest.map { String(format: "%02x", $0) }.joined()

        if expectedSha256.isEmpty || finalHex == expectedSha256 {
            // Success: Move to ~/Downloads/Corda/
            let destURL = getUniqueDestinationURL(baseFolder: defaultDownloadsFolder, relativePath: relativePath)
            try? FileManager.default.moveItem(at: tempURL, to: destURL)
            #if DEBUG
            print("[DataStream] File verified successfully & saved to: \(destURL.path)")
            #endif
        } else {
            #if DEBUG
            print("[DataStream] Whole-file SHA256 mismatch! Expected: \(expectedSha256), Got: \(finalHex). Deleting corrupt file.")
            #endif
            try? FileManager.default.removeItem(at: tempURL)
        }

        currentTempFileURL = nil
        currentFileIndex += 1
    }

    private func handleTransferComplete() {
        DispatchQueue.main.async {
            NSSound(named: "Glass")?.play()
            if let cur = self.activeTransfer {
                self.activeTransfer = ActiveTransferProgress(
                    id: cur.id,
                    direction: cur.direction,
                    currentFileName: "Transfer Selesai",
                    totalFiles: cur.totalFiles,
                    currentFileIndex: cur.totalFiles,
                    totalBytes: cur.totalBytes,
                    transferredBytes: cur.totalBytes,
                    progressFraction: 1.0,
                    speedMBs: 0.0,
                    isCompleted: true
                )
            }
        }
        cleanupReceivingSession()
    }

    private func updateTransferProgress() {
        let now = Date()
        let elapsed = max(0.001, now.timeIntervalSince(transferStartTime))
        let speedMBs = (Double(currentTransferTransferredBytes) / (1024.0 * 1024.0)) / elapsed

        guard let metadata = currentReceiveMetadata else { return }
        let totalBytes = metadata["total_bytes"] as? Int64 ?? 1
        let files = metadata["files"] as? [[String: Any]] ?? []
        let currentFileName = (currentFileIndex < files.count) ? (files[currentFileIndex]["name"] as? String ?? "File") : "Selesai"
        let fraction = min(1.0, Double(currentTransferTransferredBytes) / Double(max(1, totalBytes)))

        DispatchQueue.main.async {
            self.activeTransfer = ActiveTransferProgress(
                id: metadata["transfer_id"] as? String ?? "",
                direction: "incoming",
                currentFileName: currentFileName,
                totalFiles: files.count,
                currentFileIndex: self.currentFileIndex,
                totalBytes: totalBytes,
                transferredBytes: self.currentTransferTransferredBytes,
                progressFraction: fraction,
                speedMBs: speedMBs,
                isCompleted: fraction >= 1.0
            )
        }
    }

    private func cleanupReceivingSession() {
        currentFileWriter?.closeFile()
        currentFileWriter = nil
        if let temp = currentTempFileURL {
            try? FileManager.default.removeItem(at: temp)
            currentTempFileURL = nil
        }
        activeDataConnection?.cancel()
        activeDataConnection = nil
    }

    // MARK: - Binary Frame Sender (Mac -> Android)

    /// Send a list of file URLs to the connected Android device.
    public func sendFiles(urls: [URL], to peer: ConnectedPeer) {
        queue.async {
            self.executeSendFiles(urls: urls, to: peer)
        }
    }

    private func executeSendFiles(urls: [URL], to peer: ConnectedPeer) {
        let transferId = UUID()
        var manifest: [TransferFileItem] = []
        var totalBytes: Int64 = 0
        var validURLs: [URL] = []

        // 1. Scan and compute SHA-256 for all files in manifest
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            validURLs.append(url)

            if isDir.boolValue {
                // Folder traversal
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
                    for case let fileURL as URL in enumerator {
                        var subDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &subDir), !subDir.boolValue {
                            if let item = createTransferItem(for: fileURL, relativeTo: url.deletingLastPathComponent()) {
                                manifest.append(item)
                                totalBytes += item.sizeBytes
                            }
                        }
                    }
                }
            } else {
                if let item = createTransferItem(for: url, relativeTo: url.deletingLastPathComponent()) {
                    manifest.append(item)
                    totalBytes += item.sizeBytes
                }
            }
        }

        guard !manifest.isEmpty else { return }

        // Store pending outgoing transfer
        let pending = PendingOutgoingTransfer(
            transferId: transferId,
            manifest: manifest,
            totalBytes: totalBytes,
            fileURLs: validURLs
        )
        self.pendingOutgoingTransfers[transferId] = pending

        // 2. Announce FILE_METADATA_HEADER on Control Channel (Port 54321)
        let metadataPayload: [String: Any] = [
            "type": "FILE_METADATA_HEADER",
            "transfer_id": transferId.uuidString,
            "direction": "mac_to_android",
            "total_files": manifest.count,
            "total_bytes": totalBytes,
            "files": manifest.map { [
                "name": $0.name,
                "relative_path": $0.relativePath,
                "size_bytes": $0.sizeBytes,
                "sha256": $0.sha256
            ] },
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        if let metaData = try? JSONSerialization.data(withJSONObject: metadataPayload),
           let jsonStr = String(data: metaData, encoding: .utf8) {
            let lineData = Data((jsonStr + "\n").utf8)
            peer.connection.send(content: lineData, completion: .idempotent)
        }

        // Initialize progress state
        self.transferStartTime = Date()

        DispatchQueue.main.async {
            self.activeTransfer = ActiveTransferProgress(
                id: transferId.uuidString,
                direction: "outgoing",
                currentFileName: manifest.first?.name ?? "File",
                totalFiles: manifest.count,
                currentFileIndex: 0,
                totalBytes: totalBytes,
                transferredBytes: 0,
                progressFraction: 0.0,
                speedMBs: 0.0,
                isCompleted: false
            )
        }
    }

    /// Stream binary chunks to the data channel connection (Port 54322).
    public func streamOutgoingTransfer(_ pending: PendingOutgoingTransfer, on connection: NWConnection) {
        self.transferStartTime = Date()
        var transferredBytes: Int64 = 0

        for (fileIdx, fileItem) in pending.manifest.enumerated() {
            guard let fileURL = pending.fileURLs.first(where: { $0.lastPathComponent == fileItem.name }) ?? pending.fileURLs.first,
                  let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
                continue
            }

            let totalChunks = Int(ceil(Double(fileItem.sizeBytes) / Double(Self.chunkSize)))
            var chunkIdx = 0

            while chunkIdx < totalChunks || (totalChunks == 0 && chunkIdx == 0) {
                let chunkData = fileHandle.readData(ofLength: Self.chunkSize)
                if chunkData.isEmpty && chunkIdx > 0 { break }

                let frameHeader = buildBinaryFrameHeader(
                    msgType: 0x01, // CHUNK_DATA
                    transferId: pending.transferId,
                    fileIndex: UInt32(fileIdx),
                    chunkIndex: UInt32(chunkIdx),
                    totalChunks: UInt32(max(1, totalChunks)),
                    payloadLength: UInt32(chunkData.count)
                )

                let chunkHash = Data(SHA256.hash(data: chunkData))
                var completeFrame = frameHeader
                completeFrame.append(chunkData)
                completeFrame.append(chunkHash)

                connection.send(content: completeFrame, completion: .idempotent)
                transferredBytes += Int64(chunkData.count)
                chunkIdx += 1

                let elapsed = max(0.001, Date().timeIntervalSince(self.transferStartTime))
                let speed = (Double(transferredBytes) / (1024.0 * 1024.0)) / elapsed
                let fraction = min(1.0, Double(transferredBytes) / Double(max(1, pending.totalBytes)))

                DispatchQueue.main.async {
                    self.activeTransfer = ActiveTransferProgress(
                        id: pending.transferId.uuidString,
                        direction: "outgoing",
                        currentFileName: fileItem.name,
                        totalFiles: pending.manifest.count,
                        currentFileIndex: fileIdx,
                        totalBytes: pending.totalBytes,
                        transferredBytes: transferredBytes,
                        progressFraction: fraction,
                        speedMBs: speed,
                        isCompleted: false
                    )
                }

                if chunkData.isEmpty { break }
            }

            fileHandle.closeFile()

            // Send FILE_COMPLETE frame
            let fileCompleteHeader = buildBinaryFrameHeader(
                msgType: 0x02,
                transferId: pending.transferId,
                fileIndex: UInt32(fileIdx),
                chunkIndex: 0,
                totalChunks: UInt32(totalChunks),
                payloadLength: 0
            )
            connection.send(content: fileCompleteHeader, completion: .idempotent)
        }

        // Send TRANSFER_COMPLETE frame
        let transferCompleteHeader = buildBinaryFrameHeader(
            msgType: 0x03,
            transferId: pending.transferId,
            fileIndex: 0,
            chunkIndex: 0,
            totalChunks: 0,
            payloadLength: 0
        )
        connection.send(content: transferCompleteHeader, completion: .idempotent)

        DispatchQueue.main.async {
            NSSound(named: "Glass")?.play()
            self.activeTransfer = ActiveTransferProgress(
                id: pending.transferId.uuidString,
                direction: "outgoing",
                currentFileName: "Transfer Selesai",
                totalFiles: pending.manifest.count,
                currentFileIndex: pending.manifest.count,
                totalBytes: pending.totalBytes,
                transferredBytes: pending.totalBytes,
                progressFraction: 1.0,
                speedMBs: 0.0,
                isCompleted: true
            )
        }
    }

    private func buildBinaryFrameHeader(
        msgType: UInt8,
        transferId: UUID,
        fileIndex: UInt32,
        chunkIndex: UInt32,
        totalChunks: UInt32,
        payloadLength: UInt32
    ) -> Data {
        var data = Data()
        data.append(contentsOf: Self.magicBytes) // 0..3: CORD
        data.append(0x01) // 4: Version 1
        data.append(msgType) // 5: Msg Type
        data.append(contentsOf: [0x00, 0x00]) // 6..7: Reserved

        // 8..23: 16-byte UUID
        let uuidBytes = withUnsafeBytes(of: transferId.uuid) { Array($0) }
        data.append(contentsOf: uuidBytes)

        // 24..27: File Index (UInt32 Big-Endian)
        var beFileIdx = fileIndex.bigEndian
        data.append(Data(bytes: &beFileIdx, count: 4))

        // 28..31: Chunk Index (UInt32 Big-Endian)
        var beChunkIdx = chunkIndex.bigEndian
        data.append(Data(bytes: &beChunkIdx, count: 4))

        // 32..35: Total Chunks (UInt32 Big-Endian)
        var beTotalChunks = totalChunks.bigEndian
        data.append(Data(bytes: &beTotalChunks, count: 4))

        // 36..39: Payload Length N (UInt32 Big-Endian)
        var bePayloadLen = payloadLength.bigEndian
        data.append(Data(bytes: &bePayloadLen, count: 4))

        return data
    }

    private func createTransferItem(for fileURL: URL, relativeTo baseURL: URL) -> TransferFileItem? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }

        let relativePath = fileURL.path.replacingOccurrences(of: baseURL.path + "/", with: "")
        let hash = computeFileSHA256(url: fileURL)

        return TransferFileItem(
            name: fileURL.lastPathComponent,
            relativePath: relativePath,
            sizeBytes: size,
            sha256: hash
        )
    }

    private func computeFileSHA256(url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { handle.closeFile() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: Self.chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func getUniqueDestinationURL(baseFolder: URL, relativePath: String) -> URL {
        let target = baseFolder.appendingPathComponent(relativePath)
        let parent = target.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: target.path) {
            return target
        }

        let ext = target.pathExtension
        let nameWithoutExt = target.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            let candidate = parent.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
