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
    @Published public var batteryLevel: Int? = nil
    @Published public var isCharging: Bool = false
    @Published public var powerSource: String = "battery"

    public init(
        id: String,
        name: String,
        platform: String,
        fingerprint: String,
        connection: NWConnection,
        isTrusted: Bool,
        lastActive: Date = Date(),
        batteryLevel: Int? = nil,
        isCharging: Bool = false,
        powerSource: String = "battery"
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.fingerprint = fingerprint
        self.connection = connection
        self.isTrusted = isTrusted
        self.lastActive = lastActive
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.powerSource = powerSource
    }
}

public struct MirroredAppInfo: Identifiable, Hashable {
    public var id: String { packageName }
    public let packageName: String
    public let appName: String
    public let isEnabled: Bool

    public init(packageName: String, appName: String, isEnabled: Bool) {
        self.packageName = packageName
        self.appName = appName
        self.isEnabled = isEnabled
    }
}

/// Server coordinating incoming TCP control connections on Port 54321,
/// executing the in-band pairing handshake, and broadcasting clipboard sync messages.
public final class ControlSessionServer: ObservableObject {
    public static let shared = ControlSessionServer()

    @Published public private(set) var connectedPeers: [ConnectedPeer] = []
    @Published public var latestBatteryLevel: Int? = nil
    @Published public var latestIsCharging: Bool = false
    @Published public var latestPowerSource: String = "battery"
    @Published public var whitelistedApps: [MirroredAppInfo] = []
    @Published public var isNotificationMasterEnabled: Bool = true
    @Published public var isAllAppsEnabled: Bool = false
    @Published public var isAllSystemEnabled: Bool = false
    @Published public var blacklistedApps: Set<String> = []
    @Published public var lastWhitelistSyncTime: Date? = nil

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
        let trustedList = KeychainManager.shared.getTrustedDevices()
        let defaultTrusted = trustedList.sorted(by: { $0.pairedAt > $1.pairedAt }).first
        let tempPeer = ConnectedPeer(
            id: peerId,
            name: defaultTrusted?.name ?? "Android Device",
            platform: "android",
            fingerprint: defaultTrusted?.fingerprint ?? "",
            connection: connection,
            isTrusted: defaultTrusted != nil
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

    /// Disconnect and unregister a connected companion by its fingerprint.
    public func disconnectPeer(fingerprint: String) {
        let targets = connectedPeers.filter { $0.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame }
        for p in targets {
            p.connection.cancel()
            removeConnection(p.connection)
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

        // In-band fingerprint authentication: automatically identify and trust reconnected devices
        if let fp = jsonObject["fingerprint"] as? String, !fp.isEmpty {
            if KeychainManager.shared.isFingerprintTrusted(fp) {
                let devName = (jsonObject["device_name"] as? String) ??
                    KeychainManager.shared.getTrustedDevices().first(where: { $0.fingerprint.caseInsensitiveCompare(fp) == .orderedSame })?.name
                DispatchQueue.main.async {
                    if !peer.isTrusted || peer.fingerprint != fp {
                        peer.isTrusted = true
                        peer.fingerprint = fp
                        if let name = devName, !name.isEmpty {
                            peer.name = name
                        }
                    }
                }
            }
        }

        switch type {
        case "PAIR_REQUEST":
            handlePairRequest(jsonObject, from: connection, peer: peer)
        case "CLIPBOARD_PAYLOAD":
            handleClipboardPayload(jsonObject, from: connection, peer: peer)
        case "FILE_METADATA_HEADER":
            FileStreamingManager.shared.prepareIncomingTransfer(metadata: jsonObject)
        case "CLIPBOARD_FILE_ANNOUNCE":
            FileStreamingManager.shared.prepareIncomingClipboardTransfer(metadata: jsonObject)
        case "HEARTBEAT_PING":
            handleHeartbeatPing(jsonObject, from: connection, peer: peer)
        case "BATTERY_STATUS":
            handleBatteryStatus(jsonObject, from: connection, peer: peer)
        case "OTP_DETECTED":
            handleOtpDetected(jsonObject, from: connection, peer: peer)
        case "NOTIFICATION_MIRROR":
            handleNotificationMirror(jsonObject, from: connection, peer: peer)
        case "NOTIFICATION_WHITELIST_SYNC":
            handleNotificationWhitelistSync(jsonObject, from: connection, peer: peer)
        default:
            #if DEBUG
            print("[ControlServer] Received unhandled message type: \(type)")
            #endif
        }
    }

    // MARK: - Battery & OTP Message Handling

    private func handleBatteryStatus(_ json: [String: Any], from connection: NWConnection, peer: ConnectedPeer) {
        guard let level = json["level"] as? Int,
              let isCharging = json["is_charging"] as? Bool else { return }
        let powerSource = (json["power_source"] as? String) ?? (isCharging ? "ac" : "battery")

        DispatchQueue.main.async {
            peer.batteryLevel = level
            peer.isCharging = isCharging
            peer.powerSource = powerSource

            if peer.isTrusted {
                self.latestBatteryLevel = level
                self.latestIsCharging = isCharging
                self.latestPowerSource = powerSource
            }
        }

        if peer.isTrusted {
            OtpNotificationManager.shared.checkBatteryThresholds(
                level: level,
                isCharging: isCharging,
                deviceName: peer.name
            )
        }
    }

    private func handleOtpDetected(_ json: [String: Any], from connection: NWConnection, peer: ConnectedPeer) {
        guard peer.isTrusted,
              let code = json["code"] as? String,
              let serviceName = json["service_name"] as? String else { return }
        let expiresIn = (json["expires_in"] as? Int) ?? 60

        OtpNotificationManager.shared.showOtpNotification(
            serviceName: serviceName,
            code: code,
            expiresIn: expiresIn
        )
    }

    private func handleNotificationMirror(_ json: [String: Any], from connection: NWConnection, peer: ConnectedPeer) {
        guard peer.isTrusted,
              let notificationId = json["notification_id"] as? String,
              let packageName = json["package_name"] as? String,
              let appName = json["app_name"] as? String else { return }
        let title = (json["title"] as? String) ?? ""
        let text = (json["text"] as? String) ?? ""

        OtpNotificationManager.shared.showNotificationMirror(
            notificationId: notificationId,
            packageName: packageName,
            appName: appName,
            title: title,
            text: text
        )
    }

    private func handleNotificationWhitelistSync(_ json: [String: Any], from connection: NWConnection, peer: ConnectedPeer) {
        guard peer.isTrusted else { return }
        let masterEnabled = (json["master_enabled"] as? Bool) ?? true
        let allApps = (json["all_apps_enabled"] as? Bool) ?? false
        let allSystem = (json["all_system_enabled"] as? Bool) ?? false
        let rawBlacklisted = (json["blacklisted_apps"] as? [String]) ?? []
        let rawApps = (json["apps"] as? [[String: Any]]) ?? []

        let apps: [MirroredAppInfo] = rawApps.compactMap { item in
            guard let pkg = item["package_name"] as? String, !pkg.isEmpty else { return nil }
            let name = (item["app_name"] as? String) ?? pkg
            let enabled = (item["is_enabled"] as? Bool) ?? true
            return MirroredAppInfo(packageName: pkg, appName: name, isEnabled: enabled)
        }

        DispatchQueue.main.async {
            self.isNotificationMasterEnabled = masterEnabled
            self.isAllAppsEnabled = allApps
            self.isAllSystemEnabled = allSystem
            self.blacklistedApps = Set(rawBlacklisted)
            self.whitelistedApps = apps
            self.lastWhitelistSyncTime = Date()
            #if DEBUG
            print("[ControlServer] Synced \(apps.count) apps, allApps=\(allApps), blacklisted=\(rawBlacklisted.count) from \(peer.name)")
            #endif
        }
    }

    /// Sends updated notification whitelist / universal mode settings to Android.
    public func sendNotificationWhitelistUpdate(
        masterEnabled: Bool? = nil,
        allAppsEnabled: Bool? = nil,
        allSystemEnabled: Bool? = nil,
        packageToToggle: String? = nil,
        packageEnabled: Bool? = nil,
        packageToBlacklist: String? = nil,
        packageBlacklisted: Bool? = nil
    ) {
        var payload: [String: Any] = [
            "type": "NOTIFICATION_WHITELIST_UPDATE",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let master = masterEnabled { payload["master_enabled"] = master }
        if let allApps = allAppsEnabled { payload["all_apps_enabled"] = allApps }
        if let allSys = allSystemEnabled { payload["all_system_enabled"] = allSys }
        if let pkg = packageToToggle, let en = packageEnabled {
            payload["package_to_toggle"] = pkg
            payload["package_enabled"] = en
        }
        if let pkg = packageToBlacklist, let bl = packageBlacklisted {
            payload["package_to_blacklist"] = pkg
            payload["package_blacklisted"] = bl
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else { return }

        let lineData = Data((jsonStr + "\n").utf8)
        for peer in connectedPeers where peer.isTrusted {
            peer.connection.send(content: lineData, completion: .idempotent)
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
            sendPairResponse(to: connection, status: "PIN_MISMATCH", reason: "Verification PIN does not match.")
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
        let fp = (json["fingerprint"] as? String) ?? peer.fingerprint
        let isTrusted = peer.isTrusted || (!fp.isEmpty && KeychainManager.shared.isFingerprintTrusted(fp))
        guard isTrusted else {
            #if DEBUG
            print("[ControlServer] Rejected clipboard from untrusted peer: \(peer.name)")
            #endif
            return
        }

        if !peer.isTrusted && !fp.isEmpty {
            let devName = KeychainManager.shared.getTrustedDevices().first(where: { $0.fingerprint.caseInsensitiveCompare(fp) == .orderedSame })?.name
            DispatchQueue.main.async {
                peer.isTrusted = true
                peer.fingerprint = fp
                if let name = devName, !name.isEmpty {
                    peer.name = name
                }
            }
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
        let localFp = (try? CryptoManager.shared.getPublicKeyFingerprint()) ?? ""
        var payload: [String: Any] = [
            "type": "CLIPBOARD_PAYLOAD",
            "content": text,
            "content_type": "text/plain",
            "content_hash": hash,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if !localFp.isEmpty {
            payload["fingerprint"] = localFp
        }

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

    private func handleHeartbeatPing(_ json: [String: Any], from connection: NWConnection, peer: ConnectedPeer) {
        if let fp = json["fingerprint"] as? String, !fp.isEmpty, KeychainManager.shared.isFingerprintTrusted(fp) {
            let devName = (json["device_name"] as? String) ??
                KeychainManager.shared.getTrustedDevices().first(where: { $0.fingerprint.caseInsensitiveCompare(fp) == .orderedSame })?.name
            DispatchQueue.main.async {
                if !peer.isTrusted || peer.fingerprint != fp {
                    peer.isTrusted = true
                    peer.fingerprint = fp
                    if let name = devName, !name.isEmpty {
                        peer.name = name
                    }
                }
            }
        }

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
