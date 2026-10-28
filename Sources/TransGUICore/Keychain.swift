import Foundation
import Security

/// Minimal Keychain wrapper for RPC passwords.
///
/// **Debug builds never touch the Keychain** (the user's standing rule):
/// `#if DEBUG` compiles `save`/`load`/`delete` into no-ops so automated
/// testing cannot block on `SecItemCopyMatching` (the startup stall that
/// caused the window no-show) and can never pollute or read the user's
/// real Keychain entries. Debug runs get their password from the
/// `SWIFTTRANSGUI_RPC_PASSWORD` environment variable instead; release
/// builds (what `Scripts/make-app.sh` produces) use the real Keychain.
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
        #if DEBUG
        return false  // debug builds never write the Keychain
        #else
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
        #endif
    }

    /// Load the stored password, if any.
    ///
    /// Interactive **by design**: no suppression mechanism works for this
    /// item on macOS 26 (both `kSecUseAuthenticationUIFail` — deprecated
    /// and ignored — and an `LAContext.interactionNotAllowed` were measured
    /// to pop the SecurityAgent dialog anyway). Startup therefore never
    /// calls this; it runs only for an explicit user Connect, where a
    /// prompt ("Always Allow" sticks while the code signature is stable) is
    /// user-owned. Debug builds never reach it at all.
    public static func load(account: String) -> String? {
        #if DEBUG
        return nil  // debug builds never read the Keychain
        #else
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
        #endif
    }

    /// Delete any stored password for `account`.
    public static func delete(account: String) {
        #if DEBUG
        return  // debug builds never touch the Keychain
        #else
        var query = baseQuery
        query[kSecAttrAccount as String] = account
        SecItemDelete(query as CFDictionary)
        #endif
    }
}
