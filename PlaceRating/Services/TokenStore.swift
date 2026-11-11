import Foundation
import Security

struct StoredTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessExpiry: Date
}

/// `load` returns nil when nothing is stored and throws when the store can't be read,
/// so a read failure is never mistaken for being signed out.
protocol TokenStore: Sendable {
    func load() throws -> StoredTokens?
    func save(_ tokens: StoredTokens) throws
    func clear() throws
}

struct KeychainError: Error, Equatable {
    let status: OSStatus
}

/// Keeps both tokens in one Keychain item, so a rotation is a single atomic write.
struct KeychainTokenStore: TokenStore {
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.magdzaky.PlaceRating.session",
            kSecAttrAccount as String: "tokens",
        ]
    }

    func load() throws -> StoredTokens? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(StoredTokens.self, from: data)
    }

    func save(_ tokens: StoredTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
