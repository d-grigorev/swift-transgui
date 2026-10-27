import AppKit
import Foundation
import TransGUICore

// MARK: - Dialog states

/// Input for the "Torrent properties" sheet: values read from the first
/// selected torrent; OK applies them to every id in `ids` (reference
/// behavior — the dialog edits the first row but mutates the whole
/// selection).
struct PropertiesSheetState: Identifiable {
    /// Torrent whose values were read (the sheet's data source).
    let id: Int
    /// All selected torrents the OK button applies to.
    let ids: [Int]
    let name: String
    var downloadLimited: Bool
    var downloadLimit: Int
    var uploadLimited: Bool
    var uploadLimit: Int
    var peerLimit: Int
    /// 0 follow global, 1 stop at ratio, 2 unlimited (tr_ratiolimit).
    var seedRatioMode: Int
    var seedRatioLimit: Double
    /// 0 follow global, 1 stop when idle, 2 unlimited (tr_inactivelimit).
    var seedIdleMode: Int
    var seedIdleLimit: Int
    /// Original tracker list for the Advanced-tab diff.
    var trackers: [Tracker]
}

/// Options edited by the "Torrent properties" sheet, applied on OK.
struct PropertiesOptions {
    var downloadLimited: Bool
    var downloadLimit: Int
    var uploadLimited: Bool
    var uploadLimit: Int
    var peerLimit: Int
    var seedRatioMode: Int
    var seedRatioLimit: Double
    var seedIdleMode: Int
    var seedIdleLimit: Int
    /// Tracker list as edited (one announce URL per line).
    var trackersText: String
}

/// Input for the "Torrent data location" sheet.
struct DataLocationSheetState: Identifiable {
    let ids: [Int]
    /// The first torrent's current location (pre-filled).
    let currentPath: String

    var id: Int { ids.first ?? 0 }
}

/// Input for the "Set labels" sheet.
struct LabelsSheetState: Identifiable {
    let ids: [Int]
    /// Existing labels of the first torrent, comma-separated (prefill).
    let initial: String

    var id: Int { ids.first ?? 0 }
}

/// Input for the "Rename" sheet (a single torrent, like the reference).
struct RenameSheetState: Identifiable {
    let id: Int
    let currentName: String
}

/// Remove confirmation for the 3-option alert (Remove / Remove and delete
/// data / Cancel).
struct RemoveConfirmState: Identifiable {
    let ids: [Int]
    /// True when invoked via "Remove torrent and Data": the message then
    /// asks about deleting the downloaded data as well.
    let asksData: Bool

    var id: Int { ids.first ?? 0 }

    var message: String {
        if asksData {
            return "Are you sure you want to remove the selected torrent(s)?\n"
                + "Also delete the downloaded data?"
        }
        return "Are you sure you want to remove the selected torrent(s)?"
    }
}

/// Verify confirmation.
struct VerifyConfirmState: Identifiable {
    let ids: [Int]

    var id: Int { ids.first ?? 0 }
}

/// Queue movement positions (`queue-move-top|up|down|bottom` — these
/// action methods are not `torrent-` prefixed).
enum QueueMove: String, CaseIterable, Sendable {
    case top, up, down, bottom
}

// MARK: - Actions

extension AppModel {
    // MARK: Availability

    /// Whether selection-based actions may run (connected + non-empty
    /// selection).
    var canAct: Bool {
        phase.isConnected && !selection.isEmpty
    }

    /// `torrent-start-now` needs RPC >= 14.
    var canForceStart: Bool {
        canAct && rpcVersion >= 14
    }

    /// `delete-local-data` needs RPC >= 4.
    var canRemoveData: Bool {
        canAct && rpcVersion >= 4
    }

    /// Labels need RPC >= 16.
    var canSetLabels: Bool {
        canAct && rpcVersion >= 16
    }

    /// `torrent-set-location` needs RPC >= 6.
    var canSetLocation: Bool {
        canAct && rpcVersion >= 6
    }

    /// `torrent-rename-path` needs RPC >= 15.
    var canRename: Bool {
        canAct && rpcVersion >= 15
    }

    // MARK: Direct actions (RPC then immediate list refresh)

    /// Start the given torrents (defaults to the selection).
    func start(ids: [Int]? = nil) async {
        await performAction("torrent-start", ids: ids ?? selection.sorted())
    }

    /// Force-start ignoring the queue (defaults to the selection).
    func forceStart(ids: [Int]? = nil) async {
        await performAction("torrent-start-now", ids: ids ?? selection.sorted())
    }

    /// Start every torrent on the server (`torrent-start` without ids).
    func startAll() async {
        await performAction("torrent-start", ids: nil)
    }

    /// Stop the given torrents (defaults to the selection).
    func stop(ids: [Int]? = nil) async {
        await performAction("torrent-stop", ids: ids ?? selection.sorted())
    }

    /// Stop every torrent on the server (`torrent-stop` without ids).
    func stopAll() async {
        await performAction("torrent-stop", ids: nil)
    }

    /// Ask the trackers to update now (defaults to the selection).
    func reannounce(ids: [Int]? = nil) async {
        await performAction("torrent-reannounce", ids: ids ?? selection.sorted())
    }

    /// Recheck local data for the given ids (`torrent-verify`).
    func verify(ids: [Int]) async {
        await performAction("torrent-verify", ids: ids)
    }

    /// Move the selection (or given ids) in the queue.
    func queueMove(ids: [Int]? = nil, position: QueueMove) async {
        await performAction(
            "queue-move-\(position.rawValue)",
            ids: ids ?? selection.sorted()
        )
    }

    /// Set the bandwidth priority (-1 low, 0 normal, 1 high).
    func setBandwidthPriority(ids: [Int]? = nil, priority: Int) async {
        guard client != nil else { return }
        let targets = ids ?? selection.sorted()
        guard !targets.isEmpty else { return }
        var args = TorrentSetArgs(ids: targets)
        args.bandwidthPriority = priority
        await sendTorrentSet(args)
    }

    /// Replace the labels of the given torrents (sorted).
    func setLabels(ids: [Int], labels: [String]) async {
        guard client != nil else { return }
        guard !ids.isEmpty else { return }
        var args = TorrentSetArgs(ids: ids)
        args.labels = labels.sorted()
        await sendTorrentSet(args)
    }

    /// Rename a torrent's root path (`torrent-rename-path`).
    func renameTorrent(id: Int, newName: String) async {
        guard let client else { return }
        guard let oldName = torrents.first(where: { $0.id == id })?.name else {
            return
        }
        guard !newName.isEmpty, newName != oldName else { return }
        do {
            let _: EmptyArguments = try await client.call(
                method: "torrent-rename-path",
                arguments: TorrentRenamePathArgs(ids: [id], path: oldName, name: newName)
            )
        } catch {
            addTorrentError = cleanMessage(error)
            return
        }
        await requestImmediateRefresh()
    }

    /// Move (or re-point) the torrent data to a new location.
    func setDataLocation(ids: [Int], path: String, moveData: Bool) async {
        guard let client else { return }
        guard !ids.isEmpty, !path.isEmpty else { return }
        do {
            let _: EmptyArguments = try await client.call(
                method: "torrent-set-location",
                arguments: TorrentSetLocationArgs(ids: ids, location: path, move: moveData)
            )
        } catch {
            addTorrentError = cleanMessage(error)
            return
        }
        await requestImmediateRefresh()
    }

    /// Copy the magnet links of the given torrents (newline-separated) to
    /// the general pasteboard.
    func copyMagnetLinks(ids: [Int]) async {
        guard let client, !ids.isEmpty else { return }
        do {
            let rows = try await client.getTorrents(fields: ["id", "magnetLink"], ids: ids)
            let links = rows.compactMap(\.magnetLink).filter { !$0.isEmpty }
            guard !links.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(links.joined(separator: "\n"), forType: .string)
        } catch {
            addTorrentError = cleanMessage(error)
        }
    }

    /// Toggle `session.alt-speed-enabled` via `session-set`, then reload
    /// the session so the toggle reflects the daemon state.
    func toggleAltSpeedEnabled() async {
        guard let client, let current = session?.altSpeedEnabled else { return }
        do {
            let _: EmptyArguments = try await client.call(
                method: "session-set",
                arguments: SessionAltSpeedArgs(altSpeedEnabled: !current)
            )
            await refresh(sessionRefresh: true)
        } catch {
            addTorrentError = cleanMessage(error)
        }
    }

    // MARK: Confirmations

    /// Ask before removing the given ids (defaults to the selection).
    func askRemove(ids: [Int]? = nil, asksData: Bool = false) {
        let targets = (ids ?? selection.sorted()).filter { $0 > 0 }
        guard !targets.isEmpty else { return }
        removeConfirm = RemoveConfirmState(ids: targets, asksData: asksData)
    }

    /// Remove the given ids, optionally deleting their local data.
    func remove(ids: [Int], deleteData: Bool) async {
        guard let client, !ids.isEmpty else { return }
        do {
            let _: EmptyArguments = try await client.call(
                method: "torrent-remove",
                arguments: TorrentRemoveArgs(ids: ids, deleteLocalData: deleteData)
            )
        } catch {
            addTorrentError = cleanMessage(error)
            return
        }
        selection.subtract(ids)
        await requestImmediateRefresh()
    }

    /// Ask before verifying the given ids (defaults to the selection).
    func askVerify(ids: [Int]? = nil) {
        let targets = (ids ?? selection.sorted()).filter { $0 > 0 }
        guard !targets.isEmpty else { return }
        verifyConfirm = VerifyConfirmState(ids: targets)
    }

    // MARK: Dialog presentation

    /// Load the "Torrent properties" values and present the sheet.
    func presentProperties(ids explicit: [Int]? = nil) async {
        guard phase.isConnected else { return }
        let ids = (explicit ?? selection.sorted()).filter { $0 > 0 }
        guard let client, let first = ids.first else { return }
        do {
            let torrent = try await client.getTorrentDetails(
                fields: PropertiesFields.all, ids: [first]
            )
            propertiesSheet = PropertiesSheetState(
                id: first,
                ids: ids,
                name: torrent.name ?? "",
                downloadLimited: torrent.downloadLimited ?? false,
                downloadLimit: max(0, torrent.downloadLimit ?? 0),
                uploadLimited: torrent.uploadLimited ?? false,
                uploadLimit: max(0, torrent.uploadLimit ?? 0),
                peerLimit: min(999, max(1, torrent.maxConnectedPeers ?? 250)),
                seedRatioMode: torrent.seedRatioMode ?? 0,
                seedRatioLimit: max(0, torrent.seedRatioLimit ?? 0),
                seedIdleMode: torrent.seedIdleMode ?? 0,
                seedIdleLimit: min(999999, max(1, torrent.seedIdleLimit ?? 30)),
                trackers: torrent.trackers ?? []
            )
        } catch {
            addTorrentError = cleanMessage(error)
        }
    }

    /// Present the "Torrent data location" sheet for the selection.
    func presentDataLocation(ids explicit: [Int]? = nil) {
        guard phase.isConnected else { return }
        let ids = (explicit ?? selection.sorted()).filter { $0 > 0 }
        guard !ids.isEmpty else { return }
        let current = torrents.first(where: { $0.id == ids[0] })?.downloadDir
            ?? session?.downloadDir ?? ""
        dataLocationSheet = DataLocationSheetState(ids: ids, currentPath: current)
    }

    /// Present the "Set labels" sheet for the selection.
    func presentLabels(ids explicit: [Int]? = nil) {
        guard phase.isConnected else { return }
        let ids = (explicit ?? selection.sorted()).filter { $0 > 0 }
        guard !ids.isEmpty else { return }
        let existing = torrents.first(where: { $0.id == ids[0] })?.labels ?? []
        labelsSheet = LabelsSheetState(ids: ids, initial: existing.joined(separator: ", "))
    }

    /// Present the "Rename" sheet for one torrent (first of the given ids
    /// or the selection).
    func presentRename(id explicit: Int? = nil) {
        guard phase.isConnected else { return }
        guard let id = explicit ?? selection.sorted().first else { return }
        guard let torrent = torrents.first(where: { $0.id == id }) else { return }
        renameSheet = RenameSheetState(id: id, currentName: torrent.name ?? "")
    }

    // MARK: Dialog application

    /// The properties sheet was confirmed: send `torrent-set` with the
    /// edited values (scalar options always, tracker edits only when the
    /// Advanced tab changed).
    func applyProperties(_ state: PropertiesSheetState, options: PropertiesOptions) async {
        propertiesSheet = nil
        guard let client else { return }
        do {
            var args = TorrentSetArgs(ids: state.ids)
            args.downloadLimited = options.downloadLimited
            args.uploadLimited = options.uploadLimited
            if options.downloadLimited {
                args.downloadLimit = options.downloadLimit
            }
            if options.uploadLimited {
                args.uploadLimit = options.uploadLimit
            }
            args.peerLimit = options.peerLimit
            args.seedRatioMode = options.seedRatioMode
            if options.seedRatioMode == 1 {
                args.seedRatioLimit = options.seedRatioLimit
            }
            args.seedIdleMode = options.seedIdleMode
            if options.seedIdleMode == 1 {
                args.seedIdleLimit = options.seedIdleLimit
            }

            let diff = TrackerDiff.compute(original: state.trackers, lines: options.trackersText)
            if !diff.add.isEmpty {
                args.trackerAdd = diff.add
            }
            if !diff.remove.isEmpty {
                args.trackerRemove = diff.remove
            }
            if !diff.replace.isEmpty {
                args.trackerReplace = TrackerReplacePairs(pairs: diff.replace)
            }

            let _: EmptyArguments = try await client.call(method: "torrent-set", arguments: args)
            await requestImmediateRefresh()
        } catch {
            addTorrentError = cleanMessage(error)
        }
    }

    /// The location sheet was confirmed: apply `torrent-set-location`.
    func applyDataLocation(_ state: DataLocationSheetState, path: String, move: Bool) async {
        dataLocationSheet = nil
        await setDataLocation(ids: state.ids, path: path, moveData: move)
        AddTorrentDefaults.rememberDestination(path)
    }

    /// The labels sheet was confirmed: replace the labels of every id.
    func applyLabels(_ state: LabelsSheetState, labels: [String]) async {
        labelsSheet = nil
        await setLabels(ids: state.ids, labels: labels)
    }

    /// The rename sheet was confirmed.
    func applyRename(_ state: RenameSheetState, newName: String) async {
        renameSheet = nil
        await renameTorrent(id: state.id, newName: newName)
    }

    // MARK: Helpers

    /// Send a `torrent-set` and refresh the list (errors surface in the
    /// shared error alert).
    private func sendTorrentSet(_ args: TorrentSetArgs) async {
        guard let client else { return }
        do {
            let _: EmptyArguments = try await client.call(method: "torrent-set", arguments: args)
        } catch {
            addTorrentError = cleanMessage(error)
            return
        }
        await requestImmediateRefresh()
    }

    /// Run a torrent action method on `ids` (nil = every torrent), then
    /// refresh the list immediately.
    private func performAction(_ method: String, ids: [Int]?) async {
        guard let client else { return }
        if let ids, ids.isEmpty { return }
        do {
            let _: EmptyArguments = try await client.call(
                method: method,
                arguments: TorrentActionArgs(ids: ids)
            )
        } catch {
            addTorrentError = cleanMessage(error)
            return
        }
        await requestImmediateRefresh()
    }
}

// MARK: - Tracker diff (properties > Advanced)

/// Diff of the edited tracker lines against the original list, mirroring
/// the reference app: unchanged announce URLs are dropped first; each
/// remaining new line is then paired with the first leftover original
/// tracker as a `trackerReplace` (flat `[id, url, ...]` pair), surplus new
/// lines become `trackerAdd` and surplus original ids become
/// `trackerRemove`.
enum TrackerDiff {
    struct Result {
        var add: [String] = []
        var remove: [Int] = []
        var replace: [(id: Int, url: String)] = []
    }

    static func compute(original: [Tracker], lines: String) -> Result {
        var oldList: [(id: Int, url: String)] = original.compactMap { tracker in
            guard let id = tracker.id, let url = tracker.announce, !url.isEmpty else {
                return nil
            }
            return (id, url)
        }
        var newLines = lines
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Drop pairs that are unchanged on both sides.
        var index = 0
        while index < newLines.count {
            if let oldIndex = oldList.firstIndex(where: { $0.url == newLines[index] }) {
                oldList.remove(at: oldIndex)
                newLines.remove(at: index)
            } else {
                index += 1
            }
        }

        var result = Result()
        for url in newLines {
            if !oldList.isEmpty {
                let leftover = oldList.removeFirst()
                result.replace.append((id: leftover.id, url: url))
            } else {
                result.add.append(url)
            }
        }
        result.remove = oldList.map(\.id)
        return result
    }
}
