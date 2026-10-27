import Foundation
import Observation
import SwiftUI
import TransGUICore

/// Which sidebar groupings are shown.
public struct GroupingToggles: Equatable {
    public var folders = true
    public var labels = true
    public var trackers = true
}

/// Snapshot of the bottom details pane data for the selected torrent.
/// Each tab refresh overwrites only the slice it needs.
struct DetailsData: Equatable {
    /// General tab fields (also drives the piece bar and section headers).
    var general: Torrent?
    /// Decoded piece availability bitfield (base64 `pieces` field).
    var pieces: Data?
    /// `trackers` entries, merged positionally with `trackerStats`.
    var trackers: [Tracker]?
    var trackerStats: [TrackerStat]?
    var peers: [Peer]?
    var files: [TorrentFile]?
    var priorities: [Int]?
    var wanted: [Int]?
    var downloadDir: String?
}

/// Central application state: connection, polling and data.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case connecting
        case connected(String)
        case failed(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    // MARK: Published state

    var endpoint: RpcEndpoint = .default
    var phase: Phase = .idle

    var session: SessionInfo?
    var stats: SessionStats?
    var torrents: [Torrent] = []
    var freeSpace: Int64?

    var searchText = ""
    var filter: FilterSelection = .status(.all)
    var selection: Set<Int> = []
    var groupings = GroupingToggles()

    var showPasswordPrompt = false
    var passwordError: String?

    var rpcVersion: Int = 16
    var serverVersion: String = ""

    /// Which details tab is showing.
    var selectedDetailsTab: DetailsTab = .general
    /// Details pane data for the selected torrent (`nil` = no selection/loading).
    var details: DetailsData?

    // MARK: Add-torrent flows

    /// State of the "Add new torrent" sheet while a torrent is being added
    /// (`nil` = no sheet). Set by the add flow after the paused `torrent-add`.
    var addTorrentSheet: AddTorrentSheetState?
    /// Whether the "Add torrent link" sheet is presented.
    var showAddLinkSheet = false
    /// Duplicate-torrent confirmation (reference-style alert); nil when hidden.
    var duplicateTorrentAlert: DuplicateTorrentAlert?
    /// Error alert text for the add flows; nil when hidden.
    var addTorrentError: String?

    /// Queued add jobs (files picked/dropped or links) processed one at a
    /// time, since each one presents a modal sheet.
    var addTorrentQueue: [AddTorrentJob] = []
    /// True while an add flow is in progress (sheet up or RPCs running);
    /// prevents the queue from starting a second flow.
    var addTorrentBusy = false

    // MARK: Torrent action dialogs (M4)

    /// "Torrent properties" sheet while it is presented (nil = hidden).
    var propertiesSheet: PropertiesSheetState?
    /// "Torrent data location" sheet while it is presented.
    var dataLocationSheet: DataLocationSheetState?
    /// "Set labels" sheet while it is presented.
    var labelsSheet: LabelsSheetState?
    /// "Rename" sheet while it is presented.
    var renameSheet: RenameSheetState?
    /// Remove confirmation (3-option alert); nil when hidden.
    var removeConfirm: RemoveConfirmState?
    /// Verify confirmation; nil when hidden.
    var verifyConfirm: VerifyConfirmState?

    // MARK: Connection profiles (M6)

    /// Saved connection profiles (the built-in default is always first).
    var profiles: [ConnectionProfile] = []
    /// Id of the profile `endpoint` was built from (persisted).
    var currentProfileId: String = ConnectionProfile.defaultId

    // MARK: View state (M6)

    /// Left filter sidebar visible (View menu, persisted).
    var showFilterSidebar: Bool = AppSettings.showFilterPane
    /// Bottom details pane visible (View menu, persisted).
    var showDetailsPane: Bool = AppSettings.showInfoPane
    /// Bottom status bar visible (View menu, persisted).
    var showStatusBar: Bool = AppSettings.showStatusBar
    /// Table column visibility/order customization (persisted as JSON).
    var torrentColumnCustomization: TableColumnCustomization<Torrent> = .init()
    /// Bumped by the View menu's Search item; the search field focuses.
    var focusSearchTick = 0

    // MARK: M6 dialogs

    /// "Manage connections" sheet while it is presented.
    var showManageConnections = false
    /// Which caption/behavior the connections dialog opens with.
    var manageConnectionsMode: ManageConnectionsMode = .manage
    /// "Transmission options" sheet while it is presented.
    var transmissionOptionsSheet: TransmissionOptionsSheetState?
    /// "Application options" sheet while it is presented.
    var showApplicationOptions = false
    /// "Columns setup" sheet while it is presented.
    var showColumnsSetup = false
    /// Result of `blocklist-update` for the Tools menu alert; nil when hidden.
    var blocklistUpdateMessage: String?

    // MARK: Internal (also used by the add-flow extension in AddTorrentFlow.swift)

    var client: TransmissionClient?
    private var pollTask: Task<Void, Never>?
    private var rememberedPassword: String?
    /// Bumped whenever the details target changes (selection or tab);
    /// responses carrying an older generation are dropped.
    private var detailsGeneration = 0
    /// Counts General-tab refreshes so the `pieces` bitfield is fetched
    /// only every 4th refresh (cached in `details.pieces` otherwise).
    private var detailsFetchCount = 0
    /// Previous poll's torrent statuses, used to spot
    /// downloading → finished transitions for notifications. Empty until
    /// the first refresh after connecting (so the initial snapshot never
    /// notifies).
    private var previousStatuses: [Int: Int] = [:]

    /// UserDefaults key of the persisted table column customization.
    static let columnCustomizationKey = "TorrentColumnCustomization"

    // MARK: Lifecycle

    /// Restore the last-used connection profile and the persisted column
    /// customization.
    init() {
        let stored = ConnectionProfileStore.load()
        profiles = stored
        if let id = ConnectionProfileStore.lastProfileId,
            let profile = stored.first(where: { $0.id == id })
        {
            currentProfileId = profile.id
            endpoint = profile.endpoint
        } else {
            currentProfileId = ConnectionProfile.defaultId
            endpoint = ConnectionProfile.builtin.endpoint
        }
        if let data = UserDefaults.standard.data(forKey: Self.columnCustomizationKey),
            let customization = try? JSONDecoder().decode(
                TableColumnCustomization<Torrent>.self, from: data
            )
        {
            torrentColumnCustomization = customization
        }
    }

    // MARK: Derived

    var isBusy: Bool {
        if case .connecting = phase { return true }
        return false
    }

    var statusCaption: String {
        switch phase {
        case .idle:
            return endpoint.isConfigured ? "Disconnected" : "No server address configured"
        case .connecting:
            return "Connecting to daemon..."
        case .connected:
            return endpoint.statusCaption(version: serverVersion)
        case .failed(let message):
            return "Connection error: \(message)"
        }
    }

    var counts: FilterCounts {
        FilterCounts(torrents: torrents)
    }

    var folderGroups: [GroupOption] {
        groupings.folders ? Groupings.folders(torrents) : []
    }

    var labelGroups: [GroupOption] {
        groupings.labels ? Groupings.labels(torrents) : []
    }

    var trackerGroups: [GroupOption] {
        groupings.trackers ? Groupings.trackers(torrents) : []
    }

    var totalDownSpeed: Int64 {
        torrents.reduce(0) { $0 + $1.downSpeed }
    }

    var totalUpSpeed: Int64 {
        torrents.reduce(0) { $0 + $1.upSpeed }
    }

    /// Torrents matching the selected filter and the search box.
    var visibleTorrents: [Torrent] {
        var rows = torrents.filter { filter.matches($0) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        }
        return rows
    }

    func sorted(_ rows: [Torrent], by order: [KeyPathComparator<Torrent>]) -> [Torrent] {
        guard !order.isEmpty else { return rows }
        return rows.sorted(using: order)
    }

    // MARK: Launch

    /// Called on launch: auto-connect when a password is already stored.
    /// Named `launch()` (not `start()`) so it cannot shadow the M4
    /// torrent-start action `start(ids:)` — Swift prefers the zero-argument
    /// overload, which silently turned the Start buttons into this method.
    func launch() async {
        guard endpoint.isConfigured else { return }
        if Keychain.load(account: endpoint.keychainAccount) != nil {
            await connect()
        }
    }

    // MARK: Connection

    func connect() async {
        await connect(password: nil)
    }

    func connect(password supplied: String?) async {
        if case .connected = phase {
            disconnect()
            return
        }
        guard endpoint.isConfigured else {
            // No server address yet: ask the user to configure one.
            presentManageConnections(mode: .manage)
            return
        }
        phase = .connecting
        passwordError = nil

        let password: String
        if let supplied {
            password = supplied
        } else if let stored = Keychain.load(account: endpoint.keychainAccount) {
            password = stored
        } else if let remembered = rememberedPassword {
            password = remembered
        } else {
            phase = .idle
            showPasswordPrompt = true
            return
        }

        let client = TransmissionClient(endpoint: endpoint, password: password)
        do {
            let info: SessionInfo = try await client.call(method: "session-get")
            self.client = client
            rememberedPassword = password
            Keychain.save(password, account: endpoint.keychainAccount)
            serverVersion = info.version ?? "Transmission"
            rpcVersion = info.rpcVersion ?? 16
            session = info
            phase = .connected(endpoint.statusCaption(version: info.version))
            DownloadNotifier.requestAuthorization()
            startPolling()
            await refresh(sessionRefresh: true)
        } catch let error as RpcError where error == .unauthorized {
            Keychain.delete(account: endpoint.keychainAccount)
            rememberedPassword = nil
            phase = .idle
            passwordError = "The password was rejected by the server."
            showPasswordPrompt = true
        } catch {
            phase = .failed(cleanMessage(error))
        }
    }

    func submitPassword(_ password: String) async {
        showPasswordPrompt = false
        passwordError = nil
        await connect(password: password)
    }

    func cancelPasswordPrompt() {
        showPasswordPrompt = false
        passwordError = nil
        if case .connecting = phase {
            phase = .idle
        }
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        client = nil
        phase = .idle
        session = nil
        stats = nil
        torrents = []
        freeSpace = nil
        selection = []
        detailsGeneration += 1
        detailsFetchCount = 0
        details = nil
        // Drop any in-flight add flow (the daemon connection is gone).
        addTorrentQueue = []
        addTorrentBusy = false
        addTorrentSheet = nil
        duplicateTorrentAlert = nil
        // Drop any action dialogs (their RPCs need the connection too).
        propertiesSheet = nil
        dataLocationSheet = nil
        labelsSheet = nil
        renameSheet = nil
        removeConfirm = nil
        verifyConfirm = nil
        transmissionOptionsSheet = nil
        blocklistUpdateMessage = nil
        // Forget statuses: the next connection's first snapshot must not
        // produce download-complete notifications.
        previousStatuses = [:]
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self, self.client != nil else { return }
                let sessionRefresh = tick % 5 == 0
                await self.refresh(sessionRefresh: sessionRefresh)
                if self.client == nil { return }
                tick += 1
                // The interval comes from Application options ("Data
                // refresh interval"), so a change applies on the next tick.
                try? await Task.sleep(for: .seconds(AppSettings.refreshInterval))
            }
        }
    }

    // MARK: Refresh

    func refresh(sessionRefresh: Bool) async {
        guard let client else { return }
        do {
            let rows = try await client.getTorrents(fields: TorrentListFields.all)
            torrents = rows
            notifyCompletedDownloads(rows)

            if sessionRefresh {
                let info: SessionInfo = try await client.call(method: "session-get")
                session = info
                serverVersion = info.version ?? serverVersion
                rpcVersion = info.rpcVersion ?? rpcVersion
                if let dir = info.downloadDir {
                    let fs: FreeSpace = try await client.call(
                        method: "free-space",
                        arguments: FreeSpaceArgs(path: dir)
                    )
                    freeSpace = fs.sizeBytes
                }
            }

            if case .failed = phase {
                phase = .connected(endpoint.statusCaption(version: serverVersion))
            }
            pruneSelection()
            await refreshDetails(generation: detailsGeneration)
        } catch let error as RpcError where error == .unauthorized {
            disconnect()
            passwordError = "The password was rejected by the server."
            showPasswordPrompt = true
        } catch {
            phase = .failed(cleanMessage(error))
        }
    }

    /// Ask for a fresh refresh after a local mutation (used by actions later).
    func requestImmediateRefresh() async {
        guard client != nil else { return }
        await refresh(sessionRefresh: false)
    }

    private func pruneSelection() {
        let known = Set(torrents.map(\.id))
        let pruned = selection.intersection(known)
        if pruned != selection {
            selection = pruned
        }
    }

    /// Post a "Download complete" notification for every torrent observed
    /// moving from downloading to a finished state between two polls.
    /// Only transitions seen while connected can fire: the map starts empty
    /// after each (re)connect, so the initial snapshot never notifies.
    private func notifyCompletedDownloads(_ rows: [Torrent]) {
        if !previousStatuses.isEmpty {
            for torrent in rows {
                guard previousStatuses[torrent.id] == TorrentStatus.downloading.rawValue
                else { continue }
                let status = torrent.statusValue
                let completed = status == .seeding
                    || status == .seedWait
                    || (status == .stopped && torrent.isFinishedState)
                if completed {
                    DownloadNotifier.postDownloadComplete(name: torrent.displayName)
                }
            }
        }
        var current: [Int: Int] = [:]
        current.reserveCapacity(rows.count)
        for torrent in rows {
            current[torrent.id] = torrent.status ?? -1
        }
        previousStatuses = current
    }

    // MARK: Details pane

    /// The row selection changed: drop stale details and refetch.
    func selectionForDetailsChanged() {
        detailsGeneration += 1
        detailsFetchCount = 0
        details = nil
        startDetailsFetch()
    }

    /// The details tab changed: fetch only the fields the new tab needs.
    func detailsTabChanged() {
        detailsGeneration += 1
        startDetailsFetch()
    }

    private func startDetailsFetch() {
        guard client != nil, !selection.isEmpty else { return }
        let generation = detailsGeneration
        Task { [weak self] in
            await self?.refreshDetails(generation: generation)
        }
    }

    /// Fetch the active tab's fields for the selected torrent. `generation`
    /// guards against responses that arrive after the selection/tab changed.
    private func refreshDetails(generation: Int) async {
        guard generation == detailsGeneration else { return }
        guard let id = selection.sorted().first else {
            if details != nil {
                details = nil
            }
            return
        }
        guard let client else { return }
        let tab = selectedDetailsTab

        do {
            switch tab {
            case .general:
                detailsFetchCount += 1
                let includePieces = detailsFetchCount % 4 == 1
                var fields = DetailsFields.general
                if includePieces {
                    fields.append(DetailsFields.pieces)
                }
                let torrent = try await client.getTorrentDetails(fields: fields, ids: [id])
                guard generation == detailsGeneration else { return }
                var data = details ?? DetailsData()
                data.general = torrent
                if includePieces, let encoded = torrent.pieces {
                    data.pieces = Data(base64Encoded: encoded)
                }
                details = data

            case .trackers:
                let torrent = try await client.getTorrentDetails(
                    fields: DetailsFields.trackers, ids: [id]
                )
                guard generation == detailsGeneration else { return }
                var data = details ?? DetailsData()
                data.trackers = torrent.trackers ?? []
                data.trackerStats = torrent.trackerStats ?? []
                details = data

            case .peers:
                let torrent = try await client.getTorrentDetails(
                    fields: DetailsFields.peers, ids: [id]
                )
                guard generation == detailsGeneration else { return }
                var data = details ?? DetailsData()
                data.peers = torrent.peers ?? []
                details = data

            case .files:
                let torrent = try await client.getTorrentDetails(
                    fields: DetailsFields.files, ids: [id]
                )
                guard generation == detailsGeneration else { return }
                var data = details ?? DetailsData()
                data.files = torrent.files ?? []
                data.priorities = torrent.priorities ?? []
                data.wanted = torrent.wanted ?? []
                data.downloadDir = torrent.downloadDir
                details = data

            case .statistics:
                let result: SessionStats = try await client.call(method: "session-stats")
                guard generation == detailsGeneration else { return }
                stats = result
            }
        } catch let error as RpcError where error == .unauthorized {
            disconnect()
            passwordError = "The password was rejected by the server."
            showPasswordPrompt = true
        } catch {
            // Transient details errors are ignored; the list refresh reports
            // connection problems to the user.
        }
    }

    // MARK: File actions (Files tab; reused by torrent actions later)

    /// Set files wanted/unwanted (`files-wanted` / `files-unwanted`).
    /// Re-checking also normalizes the priority, like the reference app.
    func setFileWanted(indices: [Int], wanted: Bool, torrentId: Int) async {
        guard let client, !indices.isEmpty else { return }
        var args = TorrentSetArgs(ids: [torrentId])
        if wanted {
            args.filesWanted = indices
        } else {
            args.filesUnwanted = indices
        }
        args.priorityNormal = indices
        do {
            let _: EmptyArguments = try await client.call(
                method: "torrent-set", arguments: args
            )
        } catch {
            return
        }
        await refreshDetails(generation: detailsGeneration)
    }

    /// Set the priority of files. RPC values: -1000 skip, -1 low, 0 normal,
    /// 1 high. "skip" is expressed as `files-unwanted` (the file is not
    /// downloaded at all); the other levels keep the file wanted.
    func setFilePriority(indices: [Int], priority: Int, torrentId: Int) async {
        guard let client, !indices.isEmpty else { return }
        var args = TorrentSetArgs(ids: [torrentId])
        if priority <= -1000 {
            args.filesUnwanted = indices
        } else {
            args.filesWanted = indices
            switch priority {
            case ..<0:
                args.priorityLow = indices
            case 1...:
                args.priorityHigh = indices
            default:
                args.priorityNormal = indices
            }
        }
        do {
            let _: EmptyArguments = try await client.call(
                method: "torrent-set", arguments: args
            )
        } catch {
            return
        }
        await refreshDetails(generation: detailsGeneration)
    }

    func cleanMessage(_ error: Error) -> String {
        ((error as? RpcError)?.errorDescription) ?? error.localizedDescription
    }

    // MARK: View state helpers (M6)

    /// Toggle the filter pane (View menu) and remember the choice.
    func setShowFilterPane(_ value: Bool) {
        showFilterSidebar = value
        AppSettings.showFilterPane = value
    }

    /// Toggle the details pane (View menu) and remember the choice.
    func setShowInfoPane(_ value: Bool) {
        showDetailsPane = value
        AppSettings.showInfoPane = value
    }

    /// Toggle the status bar (View menu) and remember the choice.
    func setShowStatusBar(_ value: Bool) {
        showStatusBar = value
        AppSettings.showStatusBar = value
    }

    /// View > Select all: select every row the filter/search currently shows.
    func selectAllVisible() {
        selection = Set(visibleTorrents.map(\.id))
    }

    /// View > Search: ask the toolbar search field to take focus.
    func focusSearch() {
        focusSearchTick += 1
    }

    /// Persist the table column customization (called whenever the table's
    /// `columnCustomization` binding changes).
    func saveColumnCustomization() {
        if let data = try? JSONEncoder().encode(torrentColumnCustomization) {
            UserDefaults.standard.set(data, forKey: Self.columnCustomizationKey)
        }
    }
}
