import Foundation
import Security

/// Minimal Keychain wrapper for RPC passwords.
public enum Keychain {
    public static let service = "ru.dgreenday.swifttransgui.rpc"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    /// Store (or update) a password for `account`.
    @discardableResult
    public static func save(_ password: String, account: String) -> Bool {
        let data = Data(password.utf8)

        var query = baseQuery
        query[kSecAttrAccount as String] = account

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Load the stored password, if any.
    public static func load(account: String) -> String? {
        var query = baseQuery
        query[kSecAttrAccount as String] = account
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Delete any stored password for `account`.
    public static func delete(account: String) {
        var query = baseQuery
        query[kSecAttrAccount as String] = account
        SecItemDelete(query as CFDictionary)
    }
}
