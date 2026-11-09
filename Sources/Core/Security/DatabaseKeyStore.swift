import Foundation
import Security

/// Clé de chiffrement de la base TDLib (32 octets aléatoires) conservée dans le trousseau,
/// accessible uniquement appareil déverrouillé et jamais synchronisée ni restaurée ailleurs.
enum DatabaseKeyStore {
    enum KeyStoreError: Error {
        case randomGenerationFailed(OSStatus)
        case keychain(OSStatus)
    }

    private static let service = "com.nael.telegramaccess.tdlib"
    private static let account = "database-encryption-key"
    private static let keyLength = 32

    /// Clé enregistrée, ou `nil` si elle est absente ou invalide.
    /// Lève une erreur si le trousseau est inaccessible (appareil verrouillé…) : l'appelant
    /// ne doit surtout pas en conclure que la clé n'existe pas.
    static func loadKey() throws -> Data? {
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

    /// Crée une clé aléatoire et remplace l'éventuelle clé existante.
    static func createKey() throws -> Data {
        let key = try randomKey()
        try save(key)
        return key
    }

    /// Supprime la clé (après une déconnexion). Sans effet si elle est absente.
    static func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStoreError.keychain(status)
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func save(_ key: Data) throws {
        try deleteKey()
        var attributes = baseQuery
        attributes[kSecValueData as String] = key
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.keychain(status) }
    }

    private static func randomKey() throws -> Data {
        var key = Data(count: keyLength)
        let status = key.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, keyLength, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw KeyStoreError.randomGenerationFailed(status) }
        return key
    }
}
