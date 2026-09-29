import Foundation
import Network
import Combine
import AppKit

/// Represents an active connected network client (Android companion device).
public final class ConnectedPeer: Identifiable, ObservableObject {
    public let id: String
    @Published public var name: String
    public let platform: String
    @Published public var fingerprint: String
    public let connection: NWConnection
    @Published public var isTrusted: Bool
    @Published public var lastActive: Date

    public init(
        id: String,
        name: String,
        platform: String,
        fingerprint: String,
        connection: NWConnection,
        isTrusted: Bool,
        lastActive: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.fingerprint = fingerprint
        self.connection = connection
        self.isTrusted = isTrusted
        self.lastActive = lastActive
    }
}

/// Server coordinating incoming TCP control connections on Port 54321,
/// executing the in-band pairing handshake, and broadcasting clipboard sync messages.
public final class ControlSessionServer: ObservableObject {
    public static let shared = ControlSessionServer()

    @Published public private(set) var connectedPeers: [ConnectedPeer] = []

    private let queue = DispatchQueue(label: "com.corda.mac.control.server", qos: .userInitiated)
    private var peerBuffers: [ObjectIdentifier: Data] = [:]
    private var sweepTimer: DispatchSourceTimer?
    private let maxBufferSize = 10 * 1024 * 1024 // 10 MB maximum NDJSON buffer

    private init() {
        startSweepTimer()
    }

    private func startSweepTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.checkDeadConnections()
        }
        timer.resume()
        self.sweepTimer = timer
    }

    private func checkDeadConnections() {
        let now = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var toRemove: [ConnectedPeer] = []
            for peer in self.connectedPeers {
                if now.timeIntervalSince(peer.lastActive) > 45.0 {
                    #if DEBUG
                    print("[ControlServer] Peer \(peer.name) missed 3 heartbeats (idle > 45s). Tearing down connection.")
                    #endif
                    toRemove.append(peer)
                }
            }
            for dead in toRemove {
                dead.connection.cancel()
                self.removeConnection(dead.connection)
            }
        }
    }

    /// Flush all stale connections when Mac wakes from sleep.
    public func flushStaleConnections() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.peerBuffers.removeAll()
            DispatchQueue.main.async {
                for peer in self.connectedPeers {
                    peer.connection.cancel()
                }
                self.connectedPeers.removeAll()
                #if DEBUG
                print("[ControlServer] Flushed all stale connections on system wake.")
                #endif
            }
        }
    }

    /// Handle an incoming client connection routed from NWListener.
    public func handleNewConnection(_ connection: NWConnection) {
        let peerId = UUID().uuidString
        let tempPeer = ConnectedPeer(
            id: peerId,
            name: "Android Device",
            platform: "android",
            fingerprint: "",
            connection: connection,
            isTrusted: false
        )

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                #if DEBUG
                print("[ControlServer] Connection ready from \(connection.endpoint)")
                #endif
                DispatchQueue.main.async {
                    if !self.connectedPeers.contains(where: { $0.connection === connection }) {
                        self.connectedPeers.append(tempPeer)
                    }
                }
                self.receiveNextChunk(from: connection, peer: tempPeer)
            case .failed(let error):
                #if DEBUG
                print("[ControlServer] Connection failed: \(error)")
                #endif
                self.removeConnection(connection)
            case .cancelled:
                self.removeConnection(connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func removeConnection(_ connection: NWConnection) {
        let objId = ObjectIdentifier(connection)
        queue.async {
            self.peerBuffers.removeValue(forKey: objId)
        }
        DispatchQueue.main.async {
            self.connectedPeers.removeAll { $0.connection === connection }
        }
    }

    // MARK: - NDJSON Framing & Parsing

    private func receiveNextChunk(from connection: NWConnection, peer: ConnectedPeer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty {
                self.processIncomingData(data, from: connection, peer: peer)
            }

            if isComplete || error != nil {
                self.removeConnection(connection)
                return
            }

            self.receiveNextChunk(from: connection, peer: peer)
        }
    }

    private func processIncomingData(_ newData: Data, from connection: NWConnection, peer: ConnectedPeer) {
        let objId = ObjectIdentifier(connection)
        var buffer = peerBuffers[objId] ?? Data()

        // Protect against buffer overflow (cap at maxBufferSize)
        if buffer.count + newData.count > maxBufferSize {
            buffer.removeAll()
        }
        buffer.append(newData)

        // Split buffer by newline '\n' (0x0A)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: 0..<newlineIndex)
            buffer.removeSubrange(0...newlineIndex)

            if !lineData.isEmpty {
                handleMessageLine(lineData, from: connection, peer: peer)
            }
        }

        peerBuffers[objId] = buffer
    }

    private func handleMessageLine(_ lineData: Data, from connection: NWConnection, peer: ConnectedPeer) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let type = jsonObject["type"] as? String else {
            return
        }

        DispatchQueue.main.async {
            peer.lastActive = Date()
        }

        switch type {
        case "PAIR_REQUEST":
            handlePairRequest(jsonObject, from: connection, peer: peer)
        case "CLIPBOARD_PAYLOAD":
            handleClipboardPayload(jsonObject, from: connection, peer: peer)
        case "FILE_METADATA_HEADER":
            FileStreamingManager.shared.prepareIncomingTransfer(metadata: jsonObject)
        case "HEARTBEAT_PING":
            handleHeartbeatPing(jsonObject, from: connection)
        default:
            #if DEBUG
            print("[ControlServer] Received unhandled message type: \(type)")
            #endif
        }
    }

    // MARK: - Pairing Handshake

    private func handlePairRequest(_ json: [String: Any], from connection: NWConnection, peer: ConnectedPeer) {
        guard let pin = json["pin"] as? String,
              let devIdStr = json["device_id"] as? String,
              let devName = json["device_name"] as? String,
              let platform = json["platform"] as? String,
              let pubKey = json["public_key"] as? String,
              let fingerprint = json["fingerprint"] as? String else {
            sendPairResponse(to: connection, status: "REJECTED", reason: "Invalid request format")
            return
        }

        let activePin = PairingWindowController.shared.activePin

        // Validate PIN
        guard let currentPin = activePin, currentPin == pin else {
            #if DEBUG
            print("[ControlServer] PIN mismatch. Expected: \(String(describing: activePin)), Received: \(pin)")
            #endif
            sendPairResponse(to: connection, status: "PIN_MISMATCH", reason: "Kode PIN verifikasi tidak cocok.")
            return
        }

        // Save to Keychain as Trusted Device
        let deviceUUID = UUID(uuidString: devIdStr) ?? UUID()
        let trusted = TrustedDevice(
            id: deviceUUID,
            name: devName,
            platform: platform,
            publicKeyString: pubKey,
            fingerprint: fingerprint,
            pairedAt: Date()
        )

        do {
            try KeychainManager.shared.saveTrustedDevice(trusted)
            #if DEBUG
            print("[ControlServer] Device '\(devName)' (\(fingerprint)) successfully paired & saved to Keychain.")
            #endif

            // Mark peer as trusted
            DispatchQueue.main.async {
                peer.name = devName
                peer.fingerprint = fingerprint
                peer.isTrusted = true
            }

            // Respond ACCEPTED
            sendPairResponse(to: connection, status: "ACCEPTED", reason: "Pairing success")

            // Close modal with success sound
            PairingWindowController.shared.onPairingSuccess()

        } catch {
            sendPairResponse(to: connection, status: "REJECTED", reason: "Keychain error saving trusted device")
        }
    }

    private func sendPairResponse(to connection: NWConnection, status: String, reason: String? = nil) {
        let macName = Host.current().localizedName ?? "Mac"
        let macId = UserDefaults.standard.string(forKey: "com.corda.mac.local_device_id") ?? UUID().uuidString
        let fingerprint = (try? CryptoManager.shared.getPublicKeyFingerprint()) ?? ""
        let pubKey = (try? CryptoManager.shared.getPublicKeyBase64()) ?? ""

        var payload: [String: Any] = [
            "type": "PAIR_RESPONSE",
            "device_id": macId,
            "device_name": macName,
            "platform": "macos",
            "public_key": pubKey,
            "fingerprint": fingerprint,
            "status": status,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let reason = reason {
            payload["reason"] = reason
        }

        sendMessage(payload, to: connection)
    }

    // MARK: - Clipboard Synchronization

    private func handleClipboardPayload(_ json: [String: Any], from connection: NWConnection, peer: ConnectedPeer) {
        guard let content = json["content"] as? String,
              let hash = json["content_hash"] as? String else {
            return
        }

        // Verify trusted status (either peer isTrusted or fingerprint is in Keychain)
        let isTrusted = peer.isTrusted || KeychainManager.shared.isFingerprintTrusted(peer.fingerprint)
        guard isTrusted else {
            #if DEBUG
            print("[ControlServer] Rejected clipboard from untrusted peer: \(peer.name)")
            #endif
            return
        }

        #if DEBUG
        print("[ControlServer] Received clipboard text (\(content.count) chars, hash: \(hash.prefix(8))...) from \(peer.name)")
        #endif

        // Write to macOS Pasteboard without echoing back
        MacClipboardObserver.shared.writeRemoteText(content)

        // Broadcast to other connected trusted peers (multi-device support)
        broadcastClipboard(text: content, hash: hash, excluding: connection)
    }

    /// Broadcast copied text to all connected trusted Android companions.
    public func broadcastClipboard(text: String, hash: String, excluding: NWConnection? = nil) {
        let payload: [String: Any] = [
            "type": "CLIPBOARD_PAYLOAD",
            "content": text,
            "content_type": "text/plain",
            "content_hash": hash,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        let lineData = Data((jsonString + "\n").utf8)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for peer in self.connectedPeers {
                if let ex = excluding, peer.connection === ex { continue }
                if peer.isTrusted || KeychainManager.shared.isFingerprintTrusted(peer.fingerprint) {
                    peer.connection.send(content: lineData, completion: .idempotent)
                    #if DEBUG
                    print("[ControlServer] Broadcasted clipboard to \(peer.name)")
                    #endif
                }
            }
        }
    }

    // MARK: - Heartbeat

    private func handleHeartbeatPing(_ json: [String: Any], from connection: NWConnection) {
        let seq = json["seq"] as? Int ?? 0
        let pong: [String: Any] = [
            "type": "HEARTBEAT_PONG",
            "seq": seq,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        sendMessage(pong, to: connection)
    }

    private func sendMessage(_ dict: [String: Any], to connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }
        let lineData = Data((jsonString + "\n").utf8)
        connection.send(content: lineData, completion: .idempotent)
    }
}
