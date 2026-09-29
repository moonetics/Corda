import Foundation
import Network
import Combine

/// Discovered network peer on the local subnet via Bonjour mDNS.
public struct DiscoveredDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let platform: String
    public let endpoint: NWEndpoint
    public let fingerprint: String
    public let isTrusted: Bool
    public let lastSeen: Date

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(fingerprint)
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id && lhs.fingerprint == rhs.fingerprint
    }
}

/// Manages zero-configuration mDNS service advertising and browsing for Corda on the local LAN.
public final class BonjourDiscoveryManager: ObservableObject {
    public static let shared = BonjourDiscoveryManager()

    public static let serviceType = "_corda._tcp"
    public static let defaultPort: UInt16 = 54321

    @Published public private(set) var isAdvertising: Bool = false
    @Published public private(set) var isBrowsing: Bool = false
    @Published public private(set) var discoveredDevices: [DiscoveredDevice] = []

    private var listener: NWListener?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.corda.mac.bonjour", qos: .userInitiated)
    private var localDeviceId: String

    private init() {
        // Retrieve or generate persistent device UUID
        let defaultsKey = "com.corda.mac.local_device_id"
        if let existing = UserDefaults.standard.string(forKey: defaultsKey) {
            self.localDeviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: defaultsKey)
            self.localDeviceId = newId
        }
    }

    /// Start advertising the local Mac as an available Corda node.
    public func startAdvertising(port: UInt16 = defaultPort) {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let nwListener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            let computerName = Host.current().localizedName ?? "Mac"
            let fingerprint = (try? CryptoManager.shared.getPublicKeyFingerprint()) ?? ""

            var txtRecord = NWTXTRecord()
            txtRecord["name"] = computerName
            txtRecord["model"] = "macOS"
            txtRecord["dev_id"] = localDeviceId
            txtRecord["fp"] = fingerprint
            txtRecord["v"] = "1"

            nwListener.service = NWListener.Service(
                name: "Corda-\(computerName)",
                type: Self.serviceType,
                domain: "local.",
                txtRecord: txtRecord
            )

            nwListener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isAdvertising = true
                        #if DEBUG
                        print("[Bonjour] Service \(Self.serviceType) advertising successfully on port \(port).")
                        #endif
                    case .failed(let error):
                        self?.isAdvertising = false
                        #if DEBUG
                        print("[Bonjour] Listener failed with error: \(error)")
                        #endif
                    case .cancelled:
                        self?.isAdvertising = false
                    default:
                        break
                    }
                }
            }

            self.listener = nwListener
            nwListener.start(queue: queue)
        } catch {
            #if DEBUG
            print("[Bonjour] Failed to initialize NWListener: \(error)")
            #endif
        }
    }

    /// Stop advertising the service.
    public func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
    }

    /// Start browsing for other Corda devices on the local Wi-Fi.
    public func startBrowsing() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: Self.serviceType, domain: "local.")
        let nwBrowser = NWBrowser(for: descriptor, using: parameters)

        nwBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleBrowseResults(results)
        }

        nwBrowser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isBrowsing = true
                    #if DEBUG
                    print("[Bonjour] Browser active for \(Self.serviceType).")
                    #endif
                case .failed(let error):
                    self?.isBrowsing = false
                    #if DEBUG
                    print("[Bonjour] Browser failed: \(error)")
                    #endif
                case .cancelled:
                    self?.isBrowsing = false
                default:
                    break
                }
            }
        }

        self.browser = nwBrowser
        nwBrowser.start(queue: queue)
    }

    /// Stop browsing.
    public func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var devices: [DiscoveredDevice] = []

        for result in results {
            guard case let .bonjour(txt) = result.metadata else { continue }

            let devId = txt["dev_id"] ?? UUID().uuidString
            // Skip our own advertised device
            if devId == self.localDeviceId { continue }

            let name = txt["name"] ?? "Remote Device"
            let platform = txt["model"] ?? "unknown"
            let fingerprint = txt["fp"] ?? ""
            let isTrusted = KeychainManager.shared.isFingerprintTrusted(fingerprint)

            devices.append(
                DiscoveredDevice(
                    id: devId,
                    name: name,
                    platform: platform,
                    endpoint: result.endpoint,
                    fingerprint: fingerprint,
                    isTrusted: isTrusted,
                    lastSeen: Date()
                )
            )
        }

        DispatchQueue.main.async {
            self.discoveredDevices = devices
        }
    }
}
