import Foundation
import Security

/// Clé de chiffrement de la base TDLib (32 octets aléatoires) conservée dans le trousseau,
/// accessible uniquement appareil déverrouillé et jamais synchronisée ni restaurée ailleurs.
enum DatabaseKeyStore {
    struct Key {
        let data: Data
        /// Vrai si la clé vient d'être créée (aucune base existante ne peut être lue avec).
        let isNew: Bool
    }

    enum KeyStoreError: Error {
        case randomGenerationFailed(OSStatus)
        case keychain(OSStatus)
    }

    private static let service = "com.nael.telegramaccess.tdlib"
    private static let account = "database-encryption-key"
    private static let keyLength = 32

    static func loadOrCreateKey() throws -> Key {
        if let existing = try load() {
            return Key(data: existing, isNew: false)
        }
        let key = try randomKey()
        try save(key)
        return Key(data: key, isNew: true)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == keyLength else { return nil }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeyStoreError.keychain(status)
        }
    }

    private static func save(_ key: Data) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = key
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.keychain(status) }
    }

    private static func randomKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: keyLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, keyLength, &bytes)
        guard status == errSecSuccess else { throw KeyStoreError.randomGenerationFailed(status) }
        return Data(bytes)
    }
}
