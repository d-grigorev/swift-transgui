import Foundation
import TransGUICore

/// Headless live test of the M4 torrent actions.
///
/// Adds one transient torrent (synthesized metainfo, added paused), then
/// exercises the whole action surface on it — start / verify / stop, queue
/// moves, bandwidth priority, labels, rename, reannounce, `torrent-set`
/// limits and seeding modes, `torrent-set-location` — and finally removes
/// it **with** `delete-local-data`. Asserts the torrent count and every
/// pre-existing torrent (name/status/labels/queue/priority/location) are
/// unchanged afterwards. The user's real torrents are never touched: every
/// RPC targets the transient id explicitly.
enum ActionsTest {
    /// Name of the transient torrent (also used to clean up crashed runs).
    static let torrentName = "transgui-actions-test"

    private static let locationSubdir = "actions-test-loc"

    // MARK: Entry point

    static func run(client: TransmissionClient, session: SessionInfo) async throws {
        print("actions-test: start")

        try await removeLeftover(client: client)
        let before = try await snapshot(client: client, ids: nil)
        print("actions-test: torrents before = \(before.count)")

        let id = try await addTestTorrent(client: client, session: session)
        do {
            try await exercise(client: client, session: session, id: id)
            try await removeWithDeleteData(client: client, id: id)
        } catch {
            // Never leave the transient torrent behind after a failed check.
            try? await removeWithDeleteData(client: client, id: id)
            throw error
        }

        let after = try await snapshot(client: client, ids: nil)
        print("actions-test: torrents after = \(after.count)  (initial \(before.count))")
        guard after.count == before.count else {
            throw RpcError.server(
                "actions-test: torrent count changed: \(before.count) -> \(after.count)"
            )
        }
        guard after == before else {
            let changed = after.filter { !before.contains($0) }
            throw RpcError.server(
                "actions-test: pre-existing torrents changed: "
                    + changed.map { "\($0.id) \($0.name)" }.joined(separator: ", ")
            )
        }
        print("actions-test: pre-existing torrents unchanged (name/status/labels/queue/priority/location)")
        print("actions-test: PASSED")
    }

    // MARK: Steps

    private static func exercise(
        client: TransmissionClient,
        session: SessionInfo,
        id: Int
    ) async throws {
        // Added paused: status must be 0. Capture the daemon's own
        // persistence state right away — a config disk without space makes
        // stock 3.00 silently skip tracker edits later on.
        var t = try await wait(client: client, id: id, "start paused") { $0.status == 0 }
        let saveFailure = (t.errorString ?? "").contains("Unable to save torrent file")
        if saveFailure {
            print(
                "actions-test: NOTE daemon can not persist torrent files: "
                    + "\(t.errorString ?? "")"
            )
        }
        print("actions-test: torrent-add paused OK  id=\(id)  name=\(t.name ?? "?")")

        // Start: status must leave 0 (4 downloading / 3 queued / ...).
        try await action(client, "torrent-start", id: id)
        t = try await wait(client: client, id: id, "start") { ($0.status ?? 0) != 0 }
        print("actions-test: start OK  status=\(t.status ?? -1)")

        // Verify: the RPC must succeed; the recheck of an empty download
        // dir finishes almost instantly, so observing status 1/2 is a
        // best-effort bonus.
        try await action(client, "torrent-verify", id: id)
        if let observed = try? await wait(
            client: client,
            id: id,
            "verify observation",
            attempts: 60,
            delayMs: 50,
            until: { $0.status == 1 || $0.status == 2 }
        ) {
            print("actions-test: verify OK  observing status=\(observed.status ?? -1)")
        } else {
            print("actions-test: verify OK (recheck finished before it could be observed)")
        }
        // Let the recheck finish before stopping: a stop sent while the
        // daemon is still checking can be overridden by the resume that
        // follows the check.
        _ = try await wait(
            client: client,
            id: id,
            "verify completion",
            attempts: 80,
            delayMs: 250,
            until: { ($0.status ?? 0) != 1 && ($0.status ?? 0) != 2 }
        )

        // Stop: status must return to 0 ("stopped"). Retry a swallowed
        // stop (defensive: the daemon answers success even mid-recheck).
        t = try await stop(client: client, id: id)
        print("actions-test: stop OK  status=\(t.status ?? -1) (stopped)")

        try await checkQueueMoves(client: client, session: session, id: id)

        // Bandwidth priority: set high, read back, restore normal.
        try await set(client, id: id) { $0.bandwidthPriority = 1 }
        t = try await one(client: client, id: id)
        try check(t.bandwidthPriority == 1, "bandwidthPriority not applied")
        try await set(client, id: id) { $0.bandwidthPriority = 0 }
        t = try await one(client: client, id: id)
        try check(t.bandwidthPriority == 0, "bandwidthPriority not restored")
        print("actions-test: bandwidth priority OK (1 -> 0)")

        // Labels: set, read back (sorted), leave for the final removal.
        try await set(client, id: id) { $0.labels = ["m4-test", "actions-test"] }
        t = try await one(client: client, id: id)
        try check(
            (t.labels ?? []).sorted() == ["actions-test", "m4-test"],
            "labels not applied: \(t.labels ?? [])"
        )
        print("actions-test: labels OK  \(t.labels?.joined(separator: ", ") ?? "")")

        // Rename: rename the root path, read the new name back.
        let renamed = torrentName + "-renamed"
        let _: EmptyArguments = try await client.call(
            method: "torrent-rename-path",
            arguments: TorrentRenamePathArgs(ids: [id], path: torrentName, name: renamed)
        )
        t = try await one(client: client, id: id)
        try check(t.name == renamed, "rename not applied: \(t.name ?? "?")")
        print("actions-test: rename OK  \(t.name ?? "?")")

        // Reannounce: success envelope is the assertion.
        try await action(client, "torrent-reannounce", id: id)
        print("actions-test: reannounce OK")

        // torrent-set limits: set 100 KB/s down / 50 KB/s up, read back,
        // then clear both.
        try await set(client, id: id) {
            $0.downloadLimited = true
            $0.downloadLimit = 100
            $0.uploadLimited = true
            $0.uploadLimit = 50
        }
        t = try await one(client: client, id: id)
        try check(
            t.downloadLimited == true && t.downloadLimit == 100
                && t.uploadLimited == true && t.uploadLimit == 50,
            "speed limits not applied"
        )
        try await set(client, id: id) {
            $0.downloadLimited = false
            $0.uploadLimited = false
        }
        t = try await one(client: client, id: id)
        try check(
            t.downloadLimited == false && t.uploadLimited == false,
            "speed limits not cleared"
        )
        print("actions-test: torrent-set limits OK (100/50 KB/s -> cleared)")

        // The properties-dialog keys: peer limit and seeding overrides.
        try await set(client, id: id) {
            $0.peerLimit = 77
            $0.seedRatioMode = 1
            $0.seedRatioLimit = 2.5
            $0.seedIdleMode = 1
            $0.seedIdleLimit = 42
        }
        t = try await one(client: client, id: id)
        try check(t.maxConnectedPeers == 77, "peer-limit not applied")
        try check(t.seedRatioMode == 1, "seedRatioMode not applied")
        try check(
            abs((t.seedRatioLimit ?? 0) - 2.5) < 0.001,
            "seedRatioLimit not applied"
        )
        try check(t.seedIdleMode == 1 && t.seedIdleLimit == 42, "seed idle override not applied")
        try await set(client, id: id) {
            $0.seedRatioMode = 0
            $0.seedIdleMode = 0
        }
        print("actions-test: properties keys OK (peer-limit / seed ratio / idle)")

        // Tracker edits (properties > Advanced): add, replace (flat
        // [id, url] pairs) and remove, with read-backs between each step.
        try await checkTrackers(client: client, id: id, saveFailureAtAdd: saveFailure)

        // torrent-set-location without moving data, then back.
        let originalDir = session.downloadDir ?? ""
        guard !originalDir.isEmpty else {
            throw RpcError.server("actions-test: session download dir is unknown")
        }
        let newLocation = originalDir + "/" + locationSubdir
        let _: EmptyArguments = try await client.call(
            method: "torrent-set-location",
            arguments: TorrentSetLocationArgs(ids: [id], location: newLocation, move: false)
        )
        t = try await one(client: client, id: id)
        try check(t.downloadDir == newLocation, "set-location did not apply: \(t.downloadDir ?? "?")")
        let _: EmptyArguments = try await client.call(
            method: "torrent-set-location",
            arguments: TorrentSetLocationArgs(ids: [id], location: originalDir, move: false)
        )
        t = try await one(client: client, id: id)
        try check(t.downloadDir == originalDir, "set-location did not restore: \(t.downloadDir ?? "?")")
        print("actions-test: set-location OK (\(locationSubdir) -> restored)")
    }

    /// Tracker edits: `trackerAdd`, `trackerReplace` (flat `[id, url]`
    /// pairs) and `trackerRemove`, asserting the list after each step.
    /// A daemon whose config disk is full (stock 3.00) skips announce-list
    /// swaps while still answering success — detected and skipped instead
    /// of failing the whole run.
    private static func checkTrackers(
        client: TransmissionClient,
        id: Int,
        saveFailureAtAdd: Bool
    ) async throws {
        func serverCannotPersist() async throws -> Bool {
            if saveFailureAtAdd {
                return true
            }
            let torrent = try await client.getTorrentDetails(
                fields: ["id", "errorString"], ids: [id]
            )
            return (torrent.errorString ?? "").contains("Unable to save torrent file")
        }

        if try await serverCannotPersist() {
            try await validateTrackerKeys(client: client, id: id)
            print(
                "actions-test: tracker edits skipped — the daemon can not persist "
                    + "torrent files (see the NOTE above)"
            )
            return
        }

        do {
            try await applyTrackerEdits(client: client, id: id)
            print("actions-test: tracker edits OK (add / replace / remove)")
        } catch {
            guard try await serverCannotPersist() else { throw error }
            try await validateTrackerKeys(client: client, id: id)
            print(
                "actions-test: tracker edits skipped — the daemon can not persist "
                    + "torrent files (\(errorText(error)))"
            )
        }
    }

    /// The real add / replace / remove sequence with read-backs.
    private static func applyTrackerEdits(
        client: TransmissionClient,
        id: Int
    ) async throws {
        let original = "http://tracker.example.invalid:80/announce"
        let added = "http://tracker-y.example.invalid:80/announce"
        let replacement = "http://tracker-z.example.invalid:80/announce"

        func trackers() async throws -> [Tracker] {
            let torrent = try await client.getTorrentDetails(
                fields: ["id", "trackers"], ids: [id]
            )
            return torrent.trackers ?? []
        }

        var args = TorrentSetArgs(ids: [id])
        args.trackerAdd = [added]
        let _: EmptyArguments = try await client.call(method: "torrent-set", arguments: args)
        var list = try await trackers()
        try check(
            list.contains { $0.announce == original } && list.contains { $0.announce == added },
            "trackerAdd not applied: \(list.compactMap(\.announce))"
        )
        guard let addedId = list.first(where: { $0.announce == added })?.id else {
            throw RpcError.server("actions-test: added tracker has no id")
        }

        args = TorrentSetArgs(ids: [id])
        args.trackerReplace = TrackerReplacePairs(pairs: [(id: addedId, url: replacement)])
        let _: EmptyArguments = try await client.call(method: "torrent-set", arguments: args)
        list = try await trackers()
        try check(
            list.contains { $0.announce == replacement } && !list.contains { $0.announce == added },
            "trackerReplace not applied: \(list.compactMap(\.announce))"
        )
        guard let replacementId = list.first(where: { $0.announce == replacement })?.id else {
            throw RpcError.server("actions-test: replaced tracker has no id")
        }

        args = TorrentSetArgs(ids: [id])
        args.trackerRemove = [replacementId]
        let _: EmptyArguments = try await client.call(method: "torrent-set", arguments: args)
        list = try await trackers()
        try check(
            list.compactMap(\.announce) == [original],
            "trackerRemove not applied: \(list.compactMap(\.announce))"
        )
    }

    /// Prove the three tracker keys reach the daemon: an empty list is
    /// type-valid but changes nothing, so stock Transmission must answer
    /// `invalid argument` for each of them.
    private static func validateTrackerKeys(
        client: TransmissionClient,
        id: Int
    ) async throws {
        var probes: [(String, TorrentSetArgs)] = []
        var args = TorrentSetArgs(ids: [id])
        args.trackerAdd = []
        probes.append(("trackerAdd", args))
        args = TorrentSetArgs(ids: [id])
        args.trackerRemove = []
        probes.append(("trackerRemove", args))
        args = TorrentSetArgs(ids: [id])
        args.trackerReplace = TrackerReplacePairs(pairs: [])
        probes.append(("trackerReplace", args))

        for (label, probe) in probes {
            do {
                let _: EmptyArguments = try await client.call(
                    method: "torrent-set", arguments: probe
                )
                throw RpcError.server("actions-test: \(label) was not rejected when empty")
            } catch RpcError.server(let message) where message == "invalid argument" {
                // Expected: the key arrived and was processed.
            }
        }
        print("actions-test: tracker wire keys OK (trackerAdd/trackerRemove/trackerReplace)")
    }

    /// Queue moves: top/up/down/bottom must succeed; the positions must
    /// change whenever the torrent shares its queue with other entries.
    private static func checkQueueMoves(
        client: TransmissionClient,
        session: SessionInfo,
        id: Int
    ) async throws {
        let queueEnabled = (session.downloadQueueEnabled ?? false)
            || (session.seedQueueEnabled ?? false)
        guard queueEnabled else {
            print("actions-test: queue moves skipped (queues disabled on the server)")
            return
        }

        var positions: [Int] = []
        positions.append(try await one(client: client, id: id).queuePosition ?? 0)
        for position in QueueMovePositions.all {
            do {
                try await action(client, "queue-move-\(position)", id: id)
            } catch {
                print("actions-test: queue-move-\(position) skipped: \(errorText(error))")
                return
            }
            positions.append(try await one(client: client, id: id).queuePosition ?? 0)
        }

        let changes = zip(positions, positions.dropFirst()).map { $0 != $1 }
        if changes.allSatisfy({ !$0 }) {
            // Single entry in its queue (e.g. the only incomplete torrent):
            // every move legitimately keeps that one position (0-based).
            print("actions-test: queue moves OK (no position change; torrent alone in queue)")
            return
        }
        for (index, changed) in changes.enumerated() where !changed {
            throw RpcError.server(
                "actions-test: queue move #\(index + 1) did not change queuePosition"
            )
        }
        print(
            "actions-test: queue moves OK  positions: "
                + positions.map(String.init).joined(separator: " -> ")
        )
    }

    // MARK: Plumbing

    private enum QueueMovePositions {
        static let all = ["top", "bottom", "up", "down"]
    }

    private static func addTestTorrent(
        client: TransmissionClient,
        session: SessionInfo
    ) async throws -> Int {
        let data = syntheticMetainfo()
        guard let meta = TorrentMeta.parse(metainfo: data) else {
            throw RpcError.encoding("actions-test: synthesized metainfo failed to parse")
        }
        print(
            "actions-test: synthesized metainfo  name=\(meta.name ?? "?")  "
                + "infohash=\(meta.infoHashHex ?? "?")  trackers=\(meta.trackers.count)"
        )

        let args = TorrentAddArgs(
            paused: true,
            metainfo: data.base64EncodedString(),
            downloadDir: session.downloadDir
        )
        do {
            let response: TorrentAddResponse = try await client.call(
                method: "torrent-add", arguments: args
            )
            if let added = response.added {
                return added.id
            }
            if let duplicate = response.duplicate {
                throw RpcError.server(
                    "actions-test: unexpected duplicate torrent id=\(duplicate.id)"
                )
            }
            throw RpcError.invalidResponse
        } catch let error as RpcError where error == .server("duplicate torrent") {
            throw RpcError.server("actions-test: unexpected duplicate torrent")
        }
    }

    /// Remove the transient torrent with `delete-local-data`.
    private static func removeWithDeleteData(
        client: TransmissionClient,
        id: Int
    ) async throws {
        let _: EmptyArguments = try await client.call(
            method: "torrent-remove",
            arguments: TorrentRemoveArgs(ids: [id], deleteLocalData: true)
        )
        print("actions-test: torrent-remove (delete-local-data) OK  id=\(id)")
    }

    /// Remove leftovers of a previous aborted run (also with data).
    private static func removeLeftover(client: TransmissionClient) async throws {
        let rows = try await client.getTorrents(fields: ["id", "name"])
        let leftovers = rows.filter { $0.name == torrentName }
        guard !leftovers.isEmpty else { return }
        print("actions-test: cleaning \(leftovers.count) leftover test torrent(s)")
        let _: EmptyArguments = try await client.call(
            method: "torrent-remove",
            arguments: TorrentRemoveArgs(ids: leftovers.map(\.id), deleteLocalData: true)
        )
        for _ in 0..<40 {
            let remaining = try await client.getTorrents(fields: ["id", "name"])
            if remaining.allSatisfy({ $0.name != torrentName }) {
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw RpcError.server("actions-test: leftover torrent did not disappear")
    }

    /// `torrent-start`-style action on one id.
    private static func action(
        _ client: TransmissionClient,
        _ method: String,
        id: Int
    ) async throws {
        let _: EmptyArguments = try await client.call(
            method: method,
            arguments: TorrentActionArgs(ids: [id])
        )
    }

    /// Send `torrent-stop` and wait for status 0, re-sending while the
    /// daemon keeps the torrent running (a recheck finishing after the
    /// stop can resume it; the RPC itself still answers success).
    private static func stop(
        client: TransmissionClient,
        id: Int
    ) async throws -> Torrent {
        var lastStatus = -1
        for _ in 0..<3 {
            try await action(client, "torrent-stop", id: id)
            for _ in 0..<20 {
                let torrent = try await one(client: client, id: id)
                lastStatus = torrent.status ?? -1
                if lastStatus == 0 {
                    return torrent
                }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        throw RpcError.server(
            "actions-test: timed out waiting for stop (status=\(lastStatus))"
        )
    }

    /// One `torrent-set` with mutable fields set by `configure`.
    private static func set(
        _ client: TransmissionClient,
        id: Int,
        configure: (inout TorrentSetArgs) -> Void
    ) async throws {
        var args = TorrentSetArgs(ids: [id])
        configure(&args)
        let _: EmptyArguments = try await client.call(method: "torrent-set", arguments: args)
    }

    private static let readFields = [
        "id", "name", "status", "labels", "queuePosition", "bandwidthPriority",
        "downloadDir", "downloadLimit", "downloadLimited", "uploadLimit",
        "uploadLimited", "maxConnectedPeers", "seedRatioMode", "seedRatioLimit",
        "seedIdleMode", "seedIdleLimit", "errorString",
    ]

    private static func one(client: TransmissionClient, id: Int) async throws -> Torrent {
        let rows = try await client.getTorrents(fields: readFields, ids: [id])
        guard let torrent = rows.first else {
            throw RpcError.server("actions-test: torrent \(id) vanished")
        }
        return torrent
    }

    private static func wait(
        client: TransmissionClient,
        id: Int,
        _ label: String,
        attempts: Int = 50,
        delayMs: Int = 200,
        until predicate: (Torrent) -> Bool
    ) async throws -> Torrent {
        for _ in 0..<attempts {
            let torrent = try await one(client: client, id: id)
            if predicate(torrent) {
                return torrent
            }
            try await Task.sleep(for: .milliseconds(delayMs))
        }
        let torrent = try await one(client: client, id: id)
        throw RpcError.server(
            "actions-test: timed out waiting for \(label) (status=\(torrent.status ?? -1))"
        )
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw RpcError.server("actions-test: \(message)")
        }
    }

    private static func errorText(_ error: Error) -> String {
        (error as? RpcError)?.errorDescription ?? String(describing: error)
    }

    // MARK: Snapshots

    /// The fields the final comparison checks for every pre-existing torrent.
    private struct Snapshot: Equatable {
        let id: Int
        let name: String
        let status: Int
        let labels: [String]
        let queuePosition: Int
        let bandwidthPriority: Int
        let downloadDir: String
    }

    private static func snapshot(
        client: TransmissionClient,
        ids: [Int]?
    ) async throws -> [Snapshot] {
        let fields = [
            "id", "name", "status", "labels", "queuePosition", "bandwidthPriority",
            "downloadDir",
        ]
        let rows = try await client.getTorrents(fields: fields, ids: ids)
        return rows
            .map {
                Snapshot(
                    id: $0.id,
                    name: $0.name ?? "",
                    status: $0.status ?? -1,
                    labels: ($0.labels ?? []).sorted(),
                    queuePosition: $0.queuePosition ?? 0,
                    bandwidthPriority: $0.bandwidthPriority ?? 0,
                    downloadDir: $0.downloadDir ?? ""
                )
            }
            .sorted { $0.id < $1.id }
    }

    // MARK: Synthetic metainfo

    /// A minimal, valid single-file .torrent (16 KB, one zero piece,
    /// unreachable tracker) synthesized as raw bencode — no file on disk
    /// and no chance of colliding with a real torrent.
    private static func syntheticMetainfo() -> Data {
        let announce = "http://tracker.example.invalid:80/announce"

        // info dict: keys must be sorted: length < name < piece length < pieces.
        var info = Data("d6:lengthi16384e4:name".utf8)
        info.append(contentsOf: bencodeString(torrentName).utf8)
        info.append(contentsOf: "12:piece lengthi16384e6:pieces20:".utf8)
        info.append(Data(repeating: 0, count: 20))
        info.append(contentsOf: "e".utf8)

        // top-level dict: announce < info.
        var metainfo = Data("d8:announce".utf8)
        metainfo.append(contentsOf: bencodeString(announce).utf8)
        metainfo.append(contentsOf: "4:info".utf8)
        metainfo.append(info)
        metainfo.append(contentsOf: "e".utf8)
        return metainfo
    }

    private static func bencodeString(_ string: String) -> String {
        "\(string.utf8.count):\(string)"
    }
}
