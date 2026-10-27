import AppKit
import Foundation
import TransGUICore
import UniformTypeIdentifiers

// MARK: - Flow types

/// A queued add-torrent job: raw `.torrent` bytes or a link (magnet/URL).
struct AddTorrentJob: Sendable {
    enum Source: Sendable {
        case metainfo(Data)
        case link(String)
    }

    let source: Source
}

/// The paused torrent on the server that the "Add new torrent" sheet edits.
struct AddTorrentSheetState: Identifiable {
    /// Torrent id on the server (added paused; removed again on Cancel).
    let id: Int
    /// The original add job (needed to re-add into another folder).
    let job: AddTorrentJob
    /// The torrent's name as added (source of a `torrent-rename-path`).
    let originalName: String
    let files: [TorrentFile]
    /// No files and incomplete metadata (magnet link): hide the contents
    /// group and disable "Save as".
    let isMagnet: Bool
    /// Download dir used for the paused add (the sheet re-adds if changed).
    let destination: String
    /// Peer limit to pre-fill (the torrent's `maxConnectedPeers`).
    let defaultPeerLimit: Int
}

/// Duplicate-torrent confirmation, mirroring the reference app's dialog.
struct DuplicateTorrentAlert: Identifiable {
    /// Id of the already-existing torrent (0 when it could not be resolved).
    let id: Int
    let name: String?
    /// The job that collided, kept so "Yes" can merge its trackers.
    let job: AddTorrentJob
}

/// Options collected by the "Add new torrent" sheet, applied on OK.
struct AddTorrentOptions {
    var destination: String
    var template: String
    var saveAs: String
    var peerLimit: Int
    var start: Bool
    /// Indices of the files to download (all others become unwanted).
    var checkedFiles: Set<Int>
}

// MARK: - Defaults persistence

/// UserDefaults-backed memory of the add dialog: destination history
/// (most recent first), per-folder file templates, the "Start torrent"
/// default and the last applied peer limit.
enum AddTorrentDefaults {
    private static let destinationsKey = "AddTorrentDestinations"
    private static let templatesKey = "AddTorrentTemplates"
    private static let peerLimitKey = "AddTorrentPeerLimit"

    /// Key of the `StartTorrentOnAdd` default (true when never set).
    static let startTorrentKey = "StartTorrentOnAdd"

    /// Destination history, most recent first.
    static var destinations: [String] {
        UserDefaults.standard.stringArray(forKey: destinationsKey) ?? []
    }

    /// Move `path` to the front of the history (deduplicated, capped).
    static func rememberDestination(_ path: String) {
        guard !path.isEmpty else { return }
        var history = destinations.filter { $0 != path }
        history.insert(path, at: 0)
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
        UserDefaults.standard.set(history, forKey: destinationsKey)
    }

    /// Remove one entry from the destination history (trash button).
    static func removeDestination(_ path: String) {
        let history = destinations.filter { $0 != path }
        UserDefaults.standard.set(history, forKey: destinationsKey)
    }

    /// The file template remembered for a destination folder ("" = none).
    static func template(for folder: String) -> String {
        guard !folder.isEmpty,
            let all = UserDefaults.standard.dictionary(forKey: templatesKey) as? [String: String]
        else { return "" }
        return all[folder] ?? ""
    }

    /// Remember the template applied for a destination folder.
    static func setTemplate(_ template: String, for folder: String) {
        guard !folder.isEmpty else { return }
        var all =
            (UserDefaults.standard.dictionary(forKey: templatesKey) as? [String: String]) ?? [:]
        all[folder] = template
        UserDefaults.standard.set(all, forKey: templatesKey)
    }

    /// Whether new torrents start immediately (bold warning when off).
    static var startTorrentOnAdd: Bool {
        get { UserDefaults.standard.object(forKey: startTorrentKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: startTorrentKey) }
    }

    /// Last peer limit applied by the dialog (nil = daemon default).
    static var lastPeerLimit: Int? {
        get { UserDefaults.standard.object(forKey: peerLimitKey) as? Int }
        set { UserDefaults.standard.set(newValue, forKey: peerLimitKey) }
    }
}

// MARK: - Add-torrent flow

extension AppModel {
    /// Show the open panel and queue every picked `.torrent` file.
    func pickTorrentFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let torrent = UTType(filenameExtension: "torrent") {
            panel.allowedContentTypes = [torrent]
        }
        panel.message = "Select the torrent file(s) to add."
        guard panel.runModal() == .OK else { return }
        addTorrentFiles(panel.urls)
    }

    /// Queue `.torrent` files (menu, toolbar, drag & drop) for the add flow.
    func addTorrentFiles(_ urls: [URL]) {
        guard phase.isConnected else {
            addTorrentError = "Connect to a server before adding torrents."
            return
        }
        var jobs: [AddTorrentJob] = []
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                jobs.append(AddTorrentJob(source: .metainfo(data)))
            } catch {
                addTorrentError = "Cannot read \(url.lastPathComponent)."
            }
        }
        guard !jobs.isEmpty else { return }
        addTorrentQueue.append(contentsOf: jobs)
        processNextAddTorrent()
    }

    /// Queue a link (magnet or remote .torrent URL) from the add-link dialog.
    func addTorrentLink(_ link: String) {
        guard phase.isConnected else {
            addTorrentError = "Connect to a server before adding torrents."
            return
        }
        addTorrentQueue.append(AddTorrentJob(source: .link(link)))
        processNextAddTorrent()
    }

    /// Start the next queued add job, if no flow is in progress.
    func processNextAddTorrent() {
        guard !addTorrentBusy, !addTorrentQueue.isEmpty, client != nil else { return }
        guard addTorrentSheet == nil, duplicateTorrentAlert == nil else { return }
        addTorrentBusy = true
        let job = addTorrentQueue.removeFirst()
        Task { await performAddTorrent(job) }
    }

    /// Add the job's torrent paused, then either present the options sheet
    /// or the duplicate-torrent alert.
    private func performAddTorrent(_ job: AddTorrentJob) async {
        guard let client else {
            finishAddTorrent()
            return
        }
        do {
            do {
                let response: TorrentAddResponse = try await client.call(
                    method: "torrent-add",
                    arguments: addArguments(for: job)
                )
                if let duplicate = response.duplicate {
                    presentDuplicateAlert(id: duplicate.id, name: duplicate.name, job: job)
                    return
                }
                guard let added = response.added else {
                    throw RpcError.invalidResponse
                }
                await presentAddSheet(id: added.id, job: job)
            } catch let error as RpcError where Self.isDuplicateResult(error) {
                // Older daemons report duplicates as a plain result string;
                // resolve the existing torrent by infohash like the reference.
                let existing = await findExistingTorrent(for: job)
                presentDuplicateAlert(id: existing?.id ?? 0, name: existing?.name, job: job)
            }
        } catch {
            addTorrentError = cleanMessage(error)
            finishAddTorrent()
        }
    }

    /// `torrent-add` arguments for a job: always added paused. An empty
    /// destination is omitted so the daemon uses its own default dir.
    private func addArguments(
        for job: AddTorrentJob,
        destination: String? = nil,
        peerLimit: Int? = nil
    ) -> TorrentAddArgs {
        let dir = destination ?? (session?.downloadDir ?? "")
        let peers = peerLimit ?? AddTorrentDefaults.lastPeerLimit
        switch job.source {
        case .metainfo(let data):
            return TorrentAddArgs(
                paused: true,
                metainfo: data.base64EncodedString(),
                downloadDir: dir.isEmpty ? nil : dir,
                peerLimit: peers
            )
        case .link(let link):
            return TorrentAddArgs(
                paused: true,
                filename: link,
                downloadDir: dir.isEmpty ? nil : dir,
                peerLimit: peers
            )
        }
    }

    /// Fetch the freshly added torrent and present the options sheet (or
    /// finish the add directly when Application options turned the prompt
    /// off).
    private func presentAddSheet(id: Int, job: AddTorrentJob) async {
        guard let client else {
            finishAddTorrent()
            return
        }
        guard AppSettings.promptDownloadOptions else {
            await finishDirectAdd(id: id)
            return
        }
        do {
            let torrent = try await client.getTorrentDetails(
                fields: AddTorrentFields.all, ids: [id]
            )
            let files = torrent.files ?? []
            let isMagnet = files.isEmpty
                && (torrent.metadataPercentComplete ?? 1) < 1
            let peerLimit = torrent.maxConnectedPeers ?? 250
            addTorrentSheet = AddTorrentSheetState(
                id: id,
                job: job,
                originalName: torrent.name ?? "",
                files: files,
                isMagnet: isMagnet,
                destination: session?.downloadDir ?? "",
                defaultPeerLimit: min(999, max(1, peerLimit))
            )
            // busy stays true while the sheet is up.
        } catch {
            addTorrentError = cleanMessage(error)
            await removeTorrent(id: id)
            finishAddTorrent()
        }
    }

    /// "Prompt for download options" is off: start the torrent when the
    /// remembered default says so, select it and move on — no sheet.
    private func finishDirectAdd(id: Int) async {
        guard let client else {
            finishAddTorrent()
            return
        }
        if AddTorrentDefaults.startTorrentOnAdd {
            do {
                let _: EmptyArguments = try await client.call(
                    method: "torrent-start", arguments: TorrentIdsArgs(ids: [id])
                )
            } catch {
                addTorrentError = cleanMessage(error)
            }
        }
        await requestImmediateRefresh()
        selectTorrent(id)
        finishAddTorrent()
    }

    /// The user confirmed the sheet: re-add if the destination changed,
    /// apply file selection and peer limit, rename, then start or leave
    /// paused; remember the dialog settings and select the torrent.
    func confirmAddTorrent(_ state: AddTorrentSheetState, options: AddTorrentOptions) async {
        addTorrentSheet = nil
        guard let client else {
            finishAddTorrent()
            return
        }
        do {
            var id = state.id

            // RPC 16 has no download-dir in torrent-set: remove (keeping any
            // local data) and re-add paused into the new folder.
            if options.destination != state.destination {
                let _: EmptyArguments = try await client.call(
                    method: "torrent-remove",
                    arguments: TorrentRemoveArgs(ids: [id])
                )
                let response: TorrentAddResponse = try await client.call(
                    method: "torrent-add",
                    arguments: addArguments(
                        for: state.job,
                        destination: options.destination,
                        peerLimit: options.peerLimit
                    )
                )
                guard let added = response.added else {
                    throw RpcError.server("torrent-add returned no torrent")
                }
                id = added.id
            }

            // File selection + peer limit in one torrent-set.
            var set = TorrentSetArgs(ids: [id])
            set.peerLimit = options.peerLimit
            if !state.files.isEmpty {
                let all = Set(state.files.indices)
                let wanted = options.checkedFiles.intersection(all).sorted()
                let unwanted = all.subtracting(options.checkedFiles).sorted()
                if !wanted.isEmpty {
                    set.filesWanted = wanted
                }
                if !unwanted.isEmpty {
                    set.filesUnwanted = unwanted
                }
            }
            let _: EmptyArguments = try await client.call(method: "torrent-set", arguments: set)

            // Rename when "Save as" differs from the added name.
            let newName = AddTorrentNaming.sanitized(options.saveAs)
                .trimmingCharacters(in: .whitespaces)
            if !state.isMagnet, !newName.isEmpty, newName != state.originalName {
                // A failed rename must not abort the rest of the flow.
                let _: EmptyArguments? = try? await client.call(
                    method: "torrent-rename-path",
                    arguments: TorrentRenamePathArgs(
                        ids: [id], path: state.originalName, name: newName
                    )
                )
            }

            if options.start {
                let _: EmptyArguments = try await client.call(
                    method: "torrent-start", arguments: TorrentIdsArgs(ids: [id])
                )
            }

            AddTorrentDefaults.rememberDestination(options.destination)
            AddTorrentDefaults.setTemplate(options.template, for: options.destination)
            AddTorrentDefaults.startTorrentOnAdd = options.start
            AddTorrentDefaults.lastPeerLimit = options.peerLimit

            await requestImmediateRefresh()
            selectTorrent(id)
            finishAddTorrent()
        } catch {
            addTorrentError = cleanMessage(error)
            await requestImmediateRefresh()
            finishAddTorrent()
        }
    }

    /// The user cancelled the sheet: remove the paused torrent (keeping any
    /// local data) and move on to the next queued job.
    func cancelAddTorrent(_ state: AddTorrentSheetState) async {
        addTorrentSheet = nil
        await removeTorrent(id: state.id)
        await requestImmediateRefresh()
        finishAddTorrent()
    }

    /// The alert was dismissed without a button (e.g. Escape): treat it as
    /// "No" so the add queue does not stall.
    func dismissDuplicateAlert() {
        guard duplicateTorrentAlert != nil else { return }
        duplicateTorrentAlert = nil
        finishAddTorrent()
    }

    /// Answer the duplicate-torrent alert: optionally merge the job's
    /// trackers into the existing torrent, then select it.
    func resolveDuplicateAlert(_ alert: DuplicateTorrentAlert, updateTrackers: Bool) async {
        duplicateTorrentAlert = nil
        if updateTrackers, alert.id != 0, let client {
            do {
                let existing = try await client.getTorrentDetails(
                    fields: ["id", "trackers"], ids: [alert.id]
                )
                let known = Set((existing.trackers ?? []).compactMap(\.announce))
                let incoming = trackers(of: alert.job).filter { !known.contains($0) }
                if !incoming.isEmpty {
                    let _: EmptyArguments = try await client.call(
                        method: "torrent-set",
                        arguments: TrackerAddArgs(ids: [alert.id], trackerAdd: incoming)
                    )
                }
            } catch {
                addTorrentError = cleanMessage(error)
            }
        }
        await requestImmediateRefresh()
        if alert.id != 0 {
            selectTorrent(alert.id)
        }
        finishAddTorrent()
    }

    /// Select a torrent in the list, switching the filter/search off when
    /// they would hide it (the reference app ensures the row is visible).
    func selectTorrent(_ id: Int) {
        selection = [id]
        if let torrent = torrents.first(where: { $0.id == id }) {
            if !filter.matches(torrent) {
                filter = .status(.all)
            }
            let query = searchText.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty,
                !torrent.displayName.localizedCaseInsensitiveContains(query)
            {
                searchText = ""
            }
        }
        selectionForDetailsChanged()
    }

    /// Free disk space at `path` as a formatted size ("" when unknown),
    /// used by the add dialog's "Free disk space" label.
    func freeSpaceText(at path: String) async -> String {
        guard let client, !path.isEmpty else { return "" }
        do {
            let space: FreeSpace = try await client.call(
                method: "free-space",
                arguments: FreeSpaceArgs(path: path)
            )
            guard let bytes = space.sizeBytes, bytes >= 0 else { return "" }
            return Fmt.size(bytes)
        } catch {
            return ""
        }
    }

    // MARK: Helpers

    /// Mark the current flow finished and start the next queued one.
    private func finishAddTorrent() {
        addTorrentBusy = false
        processNextAddTorrent()
    }

    private func removeTorrent(id: Int) async {
        guard let client else { return }
        do {
            let _: EmptyArguments = try await client.call(
                method: "torrent-remove",
                arguments: TorrentRemoveArgs(ids: [id])
            )
        } catch {
            return
        }
    }

    private func presentDuplicateAlert(id: Int, name: String?, job: AddTorrentJob) {
        duplicateTorrentAlert = DuplicateTorrentAlert(id: id, name: name, job: job)
        // busy stays true while the alert is up.
    }

    private static func isDuplicateResult(_ error: RpcError) -> Bool {
        if case .server(let result) = error {
            return result.lowercased() == "duplicate torrent"
        }
        return false
    }

    /// Find the torrent a job collided with, by infohash (used when the
    /// daemon only answers "duplicate torrent" without an id).
    private func findExistingTorrent(for job: AddTorrentJob) async -> Torrent? {
        let hash: String?
        switch job.source {
        case .metainfo(let data):
            hash = TorrentMeta.parse(metainfo: data)?.infoHashHex
        case .link(let link):
            hash = MagnetLink.infoHash(link)
        }
        guard let hash, let client else { return nil }
        guard let rows = try? await client.getTorrents(fields: ["id", "name", "hashString"])
        else { return nil }
        return rows.first { $0.hashString?.lowercased() == hash.lowercased() }
    }

    /// Tracker URLs a job would add (metainfo announce-list or magnet `tr`).
    private func trackers(of job: AddTorrentJob) -> [String] {
        switch job.source {
        case .metainfo(let data):
            return TorrentMeta.parse(metainfo: data)?.trackers ?? []
        case .link(let link):
            return MagnetLink.trackers(link)
        }
    }
}

// MARK: - Name sanitizing

/// "Save as" sanitizing, mirroring the reference app's ExcludeInvalidChar:
/// `* ? | < > " ~` are replaced with underscores.
enum AddTorrentNaming {
    static func sanitized(_ name: String) -> String {
        var result = ""
        for character in name {
            switch character {
            case "*", "?", "|", "<", ">", "\"", "~":
                result += "_"
            default:
                result += String(character)
            }
        }
        return result
    }
}
