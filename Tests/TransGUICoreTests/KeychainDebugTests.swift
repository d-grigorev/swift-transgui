import Testing
import TransGUICore

/// Debug builds compile the Keychain wrapper into no-ops (the standing
/// rule: automated testing must never block on or touch the user's
/// Keychain). These tests run in debug configuration — in a release build
/// the same calls would hit the real Keychain, which is exactly what the
/// `#if DEBUG` branches prevent.
@Suite("Keychain debug bypass")
struct KeychainDebugTests {
    @Test("save is a no-op that reports failure")
    func saveIsNoOp() {
        #expect(!Keychain.save("qa-should-never-store", account: "qa-should-never-store"))
    }

    @Test("load always returns nil")
    func loadIsNoOp() {
        #expect(Keychain.load(account: "qa-should-never-store") == nil)
    }

    @Test("delete is a no-op (must not crash or touch stored entries)")
    func deleteIsNoOp() {
        Keychain.delete(account: "qa-should-never-store")
    }
}
