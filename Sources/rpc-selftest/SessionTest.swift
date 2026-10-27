import Foundation
import TransGUICore

/// Headless live test of `session-set` (the M6 Transmission options save
/// path): changes ONE harmless key (`speed-limit-down`), reads it back and
/// then restores the original value **unconditionally** — even when a step
/// failed — and verifies the restore. No other session key is touched.
enum SessionTest {
    static func run(client: TransmissionClient, original: SessionInfo) async throws {
        print("session-test: start")

        // Re-read the session so the value to restore is the live one (the
        // snapshot `original` may predate other tests in this run).
        let before: SessionInfo = try await client.call(method: "session-get")
        guard let saved = before.speedLimitDown ?? original.speedLimitDown else {
            print("session-test: skipped (the daemon did not report speed-limit-down)")
            return
        }
        print("session-test: speed-limit-down = \(saved)")

        func setLimit(_ value: Int) async throws {
            var args = SessionSetArgs()
            args.speedLimitDown = value
            let _: EmptyArguments = try await client.call(
                method: "session-set", arguments: args
            )
        }

        func readLimit() async throws -> Int? {
            let info: SessionInfo = try await client.call(method: "session-get")
            return info.speedLimitDown
        }

        var failure: Error?

        do {
            try await setLimit(123)
            let readBack = try await readLimit()
            print("session-test: after set  -> speed-limit-down = \(describe(readBack))")
            guard readBack == 123 else {
                throw RpcError.server("session-test: read-back mismatch, expected 123")
            }
        } catch {
            failure = error
        }

        // Restore no matter what happened above (defer-style).
        do {
            try await setLimit(saved)
            let restored = try await readLimit()
            print("session-test: restored -> speed-limit-down = \(describe(restored))")
            guard restored == saved else {
                throw RpcError.server(
                    "session-test: restore mismatch, expected \(saved)"
                )
            }
        } catch {
            if failure == nil {
                failure = error
            }
        }

        if let failure {
            throw failure
        }
        print("session-test: PASSED")
    }

    private static func describe(_ value: Int?) -> String {
        value.map { "\($0)" } ?? "nil"
    }
}
