import Foundation
import Security

/// Represents a validated paired remote device trusted for mutual authentication.
public struct TrustedDevice: Codable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let platform: String
    public let publicKeyString: String
    public let fingerprint: String
    public let pairedAt: Date

    public init(
        id: UUID,
        name: String,
        platform: String,
        publicKeyString: String,
        fingerprint: String,
        pairedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.publicKeyString = publicKeyString
        self.fingerprint = fingerprint
        self.pairedAt = pairedAt
    }
}

/// Manages secure persistent storage of Trusted Devices inside the macOS Keychain.
public final class KeychainManager {
    public static let shared = KeychainManager()

    private let serviceName = "com.corda.mac.trusted_devices"
    private let accountKey = "trusted_devices_list"

    private init() {}

    /// Retrieve the current list of all Trusted Devices.
    public func getTrustedDevices() -> [TrustedDevice] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TrustedDevice].self, from: data)) ?? []
    }

    /// Add or update a trusted device in the Keychain.
    public func saveTrustedDevice(_ device: TrustedDevice) throws {
        var devices = getTrustedDevices()
        devices.removeAll { $0.id == device.id || $0.fingerprint.caseInsensitiveCompare(device.fingerprint) == .orderedSame }
        devices.append(device)
        try persistDeviceList(devices)
    }

    /// Remove a trusted device by its UUID.
    public func removeTrustedDevice(id: UUID) throws {
        var devices = getTrustedDevices()
        devices.removeAll { $0.id == id }
        try persistDeviceList(devices)
    }

    /// Check if a given SHA-256 fingerprint matches an authorized trusted device.
    public func isFingerprintTrusted(_ fingerprint: String) -> Bool {
        return getTrustedDevices().contains {
            $0.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame
        }
    }

    private func persistDeviceList(_ devices: [TrustedDevice]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(devices)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: "KeychainManager",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to persist trusted devices to Keychain (OSStatus \(status))"]
            )
        }
    }
}
