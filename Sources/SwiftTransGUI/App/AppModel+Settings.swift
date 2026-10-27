import Foundation
import TransGUICore

// MARK: - Transmission options (daemon settings)

/// State of the "Transmission options" sheet: the fresh `session-get`
/// snapshot the dialog was opened with.
struct TransmissionOptionsSheetState: Identifiable {
    let id = 1
    let original: SessionInfo
}

/// Encryption popup values (`session-set` uses the daemon's names).
enum TransmissionEncryption: String, CaseIterable, Identifiable, Sendable {
    case tolerated
    case preferred
    case required

    var id: String { rawValue }

    /// Reference captions for the three encryption modes.
    var title: String {
        switch self {
        case .tolerated: "Encryption disabled"
        case .preferred: "Encryption enabled"
        case .required: "Encryption required"
        }
    }

    static func from(sessionValue: String?) -> TransmissionEncryption {
        TransmissionEncryption(rawValue: sessionValue ?? "") ?? .tolerated
    }
}

/// Editable copy of the Transmission options. `sessionSetArgs()` turns the
/// draft into a `session-set` payload containing **only** the keys whose
/// value differs from `original` (nil when nothing changed).
struct TransmissionOptionsDraft: Sendable {
    let original: SessionInfo

    // Download tab
    var downloadDir: String
    var renamePartialFiles: Bool
    var incompleteDirEnabled: Bool
    var incompleteDir: String
    var seedRatioLimited: Bool
    var seedRatioLimit: Double
    var idleSeedingLimitEnabled: Bool
    var idleSeedingLimit: Int
    var cacheSizeMb: Int

    // Network (WAN) tab
    var peerPort: Int
    var peerPortRandomOnStart: Bool
    var portForwardingEnabled: Bool
    var encryption: TransmissionEncryption
    var peerLimitGlobal: Int
    var pexEnabled: Bool
    var dhtEnabled: Bool
    var lpdEnabled: Bool
    var utpEnabled: Bool
    var blocklistEnabled: Bool
    var blocklistUrl: String

    // Bandwidth tab
    var speedLimitDownEnabled: Bool
    var speedLimitDown: Int
    var speedLimitUpEnabled: Bool
    var speedLimitUp: Int
    var altSpeedEnabled: Bool
    var altSpeedDown: Int
    var altSpeedUp: Int
    var altSpeedTimeEnabled: Bool
    /// `HH:MM` fields (minutes since midnight on save).
    var timeFrom: String
    var timeTo: String
    var dayMask: Int

    // Queue tab
    var downloadQueueEnabled: Bool
    var downloadQueueSize: Int
    var seedQueueEnabled: Bool
    var seedQueueSize: Int
    var queueStalledEnabled: Bool
    var queueStalledMinutes: Int

    init(original: SessionInfo) {
        self.original = original
        downloadDir = original.downloadDir ?? ""
        renamePartialFiles = original.renamePartialFiles ?? false
        incompleteDirEnabled = original.incompleteDirEnabled ?? false
        incompleteDir = original.incompleteDir ?? ""
        seedRatioLimited = original.seedRatioLimited ?? false
        seedRatioLimit = original.seedRatioLimit ?? 2
        idleSeedingLimitEnabled = original.idleSeedingLimitEnabled ?? false
        idleSeedingLimit = original.idleSeedingLimit ?? 30
        cacheSizeMb = original.cacheSizeMb ?? 4

        peerPort = original.peerPort ?? 51413
        peerPortRandomOnStart = original.peerPortRandomOnStart ?? false
        portForwardingEnabled = original.portForwardingEnabled ?? true
        encryption = TransmissionEncryption.from(sessionValue: original.encryption)
        peerLimitGlobal = original.peerLimitGlobal ?? 500
        pexEnabled = original.pexEnabled ?? true
        dhtEnabled = original.dhtEnabled ?? true
        lpdEnabled = original.lpdEnabled ?? false
        utpEnabled = original.utpEnabled ?? true
        blocklistEnabled = original.blocklistEnabled ?? false
        blocklistUrl = original.blocklistUrl ?? ""

        speedLimitDownEnabled = original.speedLimitDownEnabled ?? false
        speedLimitDown = original.speedLimitDown ?? 100
        speedLimitUpEnabled = original.speedLimitUpEnabled ?? false
        speedLimitUp = original.speedLimitUp ?? 100
        altSpeedEnabled = original.altSpeedEnabled ?? false
        altSpeedDown = original.altSpeedDown ?? 50
        altSpeedUp = original.altSpeedUp ?? 50
        altSpeedTimeEnabled = original.altSpeedTimeEnabled ?? false
        timeFrom = Self.timeText(minutes: original.altSpeedTimeBegin ?? 540)
        timeTo = Self.timeText(minutes: original.altSpeedTimeEnd ?? 1020)
        dayMask = original.altSpeedTimeDay ?? 127

        downloadQueueEnabled = original.downloadQueueEnabled ?? true
        downloadQueueSize = original.downloadQueueSize ?? 5
        seedQueueEnabled = original.seedQueueEnabled ?? true
        seedQueueSize = original.seedQueueSize ?? 5
        queueStalledEnabled = original.queueStalledEnabled ?? true
        queueStalledMinutes = original.queueStalledMinutes ?? 60
    }

    // MARK: Time helpers

    /// Minutes since midnight → `HH:MM`.
    static func timeText(minutes: Int) -> String {
        let value = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    /// `HH:MM` → minutes since midnight (nil for anything malformed).
    static func minutes(from text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let hour = Int(parts[0].trimmingCharacters(in: .whitespaces)),
            let minute = Int(parts[1].trimmingCharacters(in: .whitespaces)),
            (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    // MARK: Diff

    /// `session-set` arguments with only the changed keys (nil = no change).
    func sessionSetArgs() -> SessionSetArgs? {
        let o = original
        var args = SessionSetArgs()
        var changed = false

        func update<T: Equatable>(_ new: T, _ old: T, _ apply: (inout SessionSetArgs, T) -> Void) {
            if new != old {
                apply(&args, new)
                changed = true
            }
        }

        // Download
        update(downloadDir, o.downloadDir ?? "") { $0.downloadDir = $1 }
        update(renamePartialFiles, o.renamePartialFiles ?? false) {
            $0.renamePartialFiles = $1
        }
        update(incompleteDirEnabled, o.incompleteDirEnabled ?? false) {
            $0.incompleteDirEnabled = $1
        }
        if incompleteDirEnabled {
            update(incompleteDir, o.incompleteDir ?? "") { $0.incompleteDir = $1 }
        }
        update(seedRatioLimited, o.seedRatioLimited ?? false) { $0.seedRatioLimited = $1 }
        if seedRatioLimited {
            update(seedRatioLimit, o.seedRatioLimit ?? 2) { $0.seedRatioLimit = $1 }
        }
        update(idleSeedingLimitEnabled, o.idleSeedingLimitEnabled ?? false) {
            $0.idleSeedingLimitEnabled = $1
        }
        if idleSeedingLimitEnabled {
            update(idleSeedingLimit, o.idleSeedingLimit ?? 30) { $0.idleSeedingLimit = $1 }
        }
        update(cacheSizeMb, o.cacheSizeMb ?? 4) { $0.cacheSizeMb = $1 }

        // Network
        update(peerPort, o.peerPort ?? 51413) { $0.peerPort = $1 }
        update(peerPortRandomOnStart, o.peerPortRandomOnStart ?? false) {
            $0.peerPortRandomOnStart = $1
        }
        update(portForwardingEnabled, o.portForwardingEnabled ?? true) {
            $0.portForwardingEnabled = $1
        }
        update(encryption, TransmissionEncryption.from(sessionValue: o.encryption)) {
            $0.encryption = $1.rawValue
        }
        update(peerLimitGlobal, o.peerLimitGlobal ?? 500) { $0.peerLimitGlobal = $1 }
        update(pexEnabled, o.pexEnabled ?? true) { $0.pexEnabled = $1 }
        update(dhtEnabled, o.dhtEnabled ?? true) { $0.dhtEnabled = $1 }
        update(lpdEnabled, o.lpdEnabled ?? false) { $0.lpdEnabled = $1 }
        update(utpEnabled, o.utpEnabled ?? true) { $0.utpEnabled = $1 }
        update(blocklistEnabled, o.blocklistEnabled ?? false) { $0.blocklistEnabled = $1 }
        if blocklistEnabled {
            update(blocklistUrl, o.blocklistUrl ?? "") { $0.blocklistUrl = $1 }
        }

        // Bandwidth
        update(speedLimitDownEnabled, o.speedLimitDownEnabled ?? false) {
            $0.speedLimitDownEnabled = $1
        }
        if speedLimitDownEnabled {
            update(speedLimitDown, o.speedLimitDown ?? 100) { $0.speedLimitDown = $1 }
        }
        update(speedLimitUpEnabled, o.speedLimitUpEnabled ?? false) {
            $0.speedLimitUpEnabled = $1
        }
        if speedLimitUpEnabled {
            update(speedLimitUp, o.speedLimitUp ?? 100) { $0.speedLimitUp = $1 }
        }
        update(altSpeedEnabled, o.altSpeedEnabled ?? false) { $0.altSpeedEnabled = $1 }
        update(altSpeedDown, o.altSpeedDown ?? 50) { $0.altSpeedDown = $1 }
        update(altSpeedUp, o.altSpeedUp ?? 50) { $0.altSpeedUp = $1 }
        update(altSpeedTimeEnabled, o.altSpeedTimeEnabled ?? false) {
            $0.altSpeedTimeEnabled = $1
        }
        if altSpeedTimeEnabled {
            if let from = Self.minutes(from: timeFrom) {
                update(from, o.altSpeedTimeBegin ?? 540) { $0.altSpeedTimeBegin = $1 }
            }
            if let to = Self.minutes(from: timeTo) {
                update(to, o.altSpeedTimeEnd ?? 1020) { $0.altSpeedTimeEnd = $1 }
            }
            update(dayMask, o.altSpeedTimeDay ?? 127) { $0.altSpeedTimeDay = $1 }
        }

        // Queue
        update(downloadQueueEnabled, o.downloadQueueEnabled ?? true) {
            $0.downloadQueueEnabled = $1
        }
        if downloadQueueEnabled {
            update(downloadQueueSize, o.downloadQueueSize ?? 5) { $0.downloadQueueSize = $1 }
        }
        update(seedQueueEnabled, o.seedQueueEnabled ?? true) { $0.seedQueueEnabled = $1 }
        if seedQueueEnabled {
            update(seedQueueSize, o.seedQueueSize ?? 5) { $0.seedQueueSize = $1 }
        }
        update(queueStalledEnabled, o.queueStalledEnabled ?? true) {
            $0.queueStalledEnabled = $1
        }
        if queueStalledEnabled {
            update(queueStalledMinutes, o.queueStalledMinutes ?? 60) {
                $0.queueStalledMinutes = $1
            }
        }

        return changed ? args : nil
    }
}

// MARK: - Settings actions

extension AppModel {
    /// Result of the `port-test` RPC (shown by the options dialog).
    enum PortTestOutcome: Sendable {
        case open
        case closed
        case failed(String)
    }

    /// Which global speed limit a status-bar menu entry changes.
    enum SpeedLimitDirection: String, Sendable {
        case down
        case up
    }

    /// Fetch a fresh `session-get` and present the "Transmission options"
    /// sheet (the reference re-reads the settings every time it opens).
    func presentTransmissionOptions() async {
        guard let client, phase.isConnected else { return }
        do {
            let info: SessionInfo = try await client.call(method: "session-get")
            transmissionOptionsSheet = TransmissionOptionsSheetState(original: info)
        } catch {
            addTorrentError = cleanMessage(error)
        }
    }

    /// The dialog was confirmed: send the changed keys and reload the
    /// session so the next open shows the daemon's own values.
    func applyTransmissionOptions(_ draft: TransmissionOptionsDraft) async {
        transmissionOptionsSheet = nil
        guard let client else { return }
        guard let args = draft.sessionSetArgs() else { return }
        do {
            let _: EmptyArguments = try await client.call(
                method: "session-set", arguments: args
            )
            await refresh(sessionRefresh: true)
        } catch {
            addTorrentError = cleanMessage(error)
        }
    }

    /// Set (or clear with nil) a global speed limit from the status-bar
    /// menu. Like the reference, picking a limit switches turtle mode off.
    func setGlobalSpeedLimit(_ direction: SpeedLimitDirection, kbps: Int?) async {
        guard let client else { return }
        var args = SessionSetArgs()
        switch direction {
        case .down:
            args.speedLimitDownEnabled = kbps != nil
            if let kbps { args.speedLimitDown = kbps }
        case .up:
            args.speedLimitUpEnabled = kbps != nil
            if let kbps { args.speedLimitUp = kbps }
        }
        args.altSpeedEnabled = false
        do {
            let _: EmptyArguments = try await client.call(
                method: "session-set", arguments: args
            )
            await refresh(sessionRefresh: true)
        } catch {
            addTorrentError = cleanMessage(error)
        }
    }

    /// `blocklist-update`; the rule count lands in `blocklistUpdateMessage`
    /// and failures surface in the shared error alert (the dev server's
    /// disk is full, so this often fails there).
    func updateBlocklist() async {
        guard let client, phase.isConnected else { return }
        do {
            let result: BlocklistUpdateResponse = try await client.call(
                method: "blocklist-update"
            )
            blocklistUpdateMessage = "Blocklist contains \(result.blocklistSize ?? 0) rules."
            await refresh(sessionRefresh: true)
        } catch {
            addTorrentError = cleanMessage(error)
        }
    }

    /// Read-only `port-test` (no settings are touched).
    func testIncomingPort() async -> PortTestOutcome {
        guard let client else { return .failed("Not connected.") }
        do {
            let test: PortTest = try await client.call(method: "port-test")
            return test.portIsOpen == true ? .open : .closed
        } catch {
            return .failed(cleanMessage(error))
        }
    }
}
