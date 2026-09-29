import Foundation
import CryptoKit
import Security

/// Manager responsible for generating and storing local device ECDSA P-256 identity keys,
/// computing SHA-256 fingerprints, and preparing TLS 1.3 credentials.
public final class CryptoManager {
    public static let shared = CryptoManager()

    private let privateKeyTag = "com.corda.mac.identity_private_key"
    private var cachedPrivateKey: P256.Signing.PrivateKey?

    private init() {}

    /// Retrieve the existing identity key from Keychain or create and store a new one.
    public func getOrCreateIdentityKey() throws -> P256.Signing.PrivateKey {
        if let cached = cachedPrivateKey {
            return cached
        }

        if let existing = loadPrivateKeyFromKeychain() {
            cachedPrivateKey = existing
            return existing
        }

        let newKey = P256.Signing.PrivateKey()
        try savePrivateKeyToKeychain(newKey)
        cachedPrivateKey = newKey
        return newKey
    }

    /// Return the raw public key bytes formatted in Base64
    public func getPublicKeyBase64() throws -> String {
        let privateKey = try getOrCreateIdentityKey()
        let publicKeyRaw = privateKey.publicKey.rawRepresentation
        return publicKeyRaw.base64EncodedString()
    }

    /// Return the standardized SHA-256 fingerprint: XX:XX:XX:...
    public func getPublicKeyFingerprint() throws -> String {
        let privateKey = try getOrCreateIdentityKey()
        let raw = privateKey.publicKey.rawRepresentation
        return Self.calculateFingerprint(for: raw)
    }

    /// Calculate standardized SHA-256 fingerprint with colon separators for any raw public key data.
    public static func calculateFingerprint(for rawPublicKey: Data) -> String {
        let hash = SHA256.hash(data: rawPublicKey)
        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    // MARK: - Keychain Private Key Storage
    private func savePrivateKeyToKeychain(_ key: P256.Signing.PrivateKey) throws {
        let keyData = key.rawRepresentation
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: privateKeyTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: "CryptoManager",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to save private key to Keychain (OSStatus \(status))"]
            )
        }
    }

    private func loadPrivateKeyFromKeychain() -> P256.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: privateKeyTag.data(using: .utf8)!,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return try? P256.Signing.PrivateKey(rawRepresentation: data)
    }
}
