import Foundation
import Security

/// Stores small secrets (the device's private identity key) in the local,
/// non-synchronizing Keychain. If the app has no Keychain entitlement (an
/// unsigned / ad-hoc "vibecoded" build hits errSecMissingEntitlement), it
/// falls back to a 0600 file in Application Support so the app still works.
///
/// The item is deliberately `ThisDeviceOnly` + non-synchronizable: identity
/// is per device and must never ride along in someone's iCloud Keychain.
public struct SecretStore: Sendable {
    public let service: String

    public static let `default` = SecretStore(service: "app.screenbridge.identity")

    public init(service: String) {
        self.service = service
    }

    public enum StoreError: Error, LocalizedError {
        case keychain(OSStatus)
        public var errorDescription: String? {
            switch self {
            case .keychain(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
                return "Keychain error \(status): \(message)"
            }
        }
    }

    public func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return try readFallback(account: account)
        case errSecMissingEntitlement, errSecNotAvailable, errSecInteractionNotAllowed:
            return try readFallback(account: account)
        default:
            throw StoreError.keychain(status)
        }
    }

    public func write(_ data: Data, account: String) throws {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecMissingEntitlement, errSecNotAvailable:
            try writeFallback(data, account: account)
        default:
            throw StoreError.keychain(status)
        }
    }

    public func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        try? FileManager.default.removeItem(at: fallbackURL(account: account))
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    // MARK: - File fallback

    private func fallbackURL(account: String) -> URL {
        StorageLocation.directory(named: "secrets")
            .appendingPathComponent("\(service).\(account).bin")
    }

    private func readFallback(account: String) throws -> Data? {
        let url = fallbackURL(account: account)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func writeFallback(_ data: Data, account: String) throws {
        let url = fallbackURL(account: account)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// App-private storage under Application Support (inside the sandbox container).
enum StorageLocation {
    static func directory(named name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("ScreenBridge", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
