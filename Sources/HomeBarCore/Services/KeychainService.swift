import Foundation
import Security

@MainActor
public protocol TokenStore {
    /** Return a saved token for a normalized server URL, or nil if absent. */
    func read(for server: String) throws -> String?
    /** Store a validated token for the given normalized server URL. */
    func save(_ token: String, for server: String) throws
}

public struct KeychainService: TokenStore {
    /** Create the app’s Keychain token store. */
    public init() {}

    /** Load the token for a normalized server URL, returning nil when no item exists. */
    public func read(for server: String) throws -> String? {
        var query = query(for: server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { throw ConnectionError.storage }
        return token
    }

    /** Atomically update or insert a validated token in the local, non-synchronizing Keychain. */
    public func save(_ token: String, for server: String) throws {
        let query = query(for: server)
        let values = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ConnectionError.storage }
        } else if status != errSecSuccess { throw ConnectionError.storage }
    }

    /** Build an exact Keychain query for this app and server. */
    private func query(for server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.jeromeberg.HomeBar.access-token",
         kSecAttrAccount as String: server,
         kSecAttrSynchronizable as String: false]
    }
}
