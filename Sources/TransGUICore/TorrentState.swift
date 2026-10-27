import Foundation

// MARK: - Status interpretation

/// Wire status values (RPC >= 14 / Transmission 2.40+ semantics).
public enum TorrentStatus: Int, Sendable {
    case stopped = 0
    case checkWait = 1
    case checking = 2
    case downloadWait = 3
    case downloading = 4
    case seedWait = 5
    case seeding = 6
}

/// User-visible torrent state (as shown in the Status column).
public enum DisplayStatus: String, Comparable, Sendable {
    case waiting = "Waiting"
    case verifying = "Verifying"
    case downloading = "Downloading"
    case seeding = "Seeding"
    case stopped = "Stopped"
    case finished = "Finished"
    case unknown = "Unknown"

    public static func < (lhs: DisplayStatus, rhs: DisplayStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var systemImage: String {
        switch self {
        case .waiting: "hourglass"
        case .verifying: "arrow.triangle.2.circlepath"
        case .downloading: "arrow.down.circle.fill"
        case .seeding: "arrow.up.circle.fill"
        case .stopped: "pause.circle.fill"
        case .finished: "checkmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

public extension Torrent {
    var statusValue: TorrentStatus {
        TorrentStatus(rawValue: status ?? -1) ?? .stopped
    }

    var isStopped: Bool {
        statusValue == .stopped
    }

    /// Stopped and fully downloaded ("Finished" pseudo-state).
    var isFinishedState: Bool {
        isStopped && isComplete
    }

    /// 100 % downloaded. `sizeWhenDone == 0` (no metadata yet) is not complete.
    var isComplete: Bool {
        guard let sizeWhenDone, sizeWhenDone > 0 else { return false }
        return (leftUntilDone ?? sizeWhenDone) == 0
    }

    var displayStatus: DisplayStatus {
        switch statusValue {
        case .checkWait, .downloadWait, .seedWait:
            return .waiting
        case .checking:
            return .verifying
        case .downloading:
            return .downloading
        case .seeding:
            return .seeding
        case .stopped:
            return isCompleteState ? .finished : .stopped
        }
    }

    private var isCompleteState: Bool {
        isStopped && isComplete
    }

    var displayName: String {
        name ?? "Unknown"
    }

    /// 0...1 progress. While verifying, shows recheck progress; while fetching
    /// metadata, shows metadata download progress.
    var progressFraction: Double {
        if statusValue == .checking {
            return max(0, min(1, recheckProgress ?? 0))
        }
        guard let sizeWhenDone else { return 0 }
        if sizeWhenDone > 0 {
            let left = Double(leftUntilDone ?? sizeWhenDone)
            let done = Double(sizeWhenDone) - left
            return max(0, min(1, done / Double(sizeWhenDone)))
        }
        // No files chosen / metadata not yet fetched.
        return max(0, min(1, metadataPercentComplete ?? 0))
    }

    var progressText: String {
        Fmt.percent(progressFraction)
    }

    var isActive: Bool {
        (rateDownload ?? 0) > 0 || (rateUpload ?? 0) > 0
    }

    /// ETA: recompute from current speed while downloading, else use the
    /// server eta (normalized: non-positive or absurd values = unknown, so
    /// they sort last instead of first).
    var effectiveEta: Int? {
        if statusValue == .downloading || statusValue == .downloadWait,
           let down = rateDownload, down > 0,
           let left = leftUntilDone, left > 0 {
            return Int(left / down)
        }
        guard let eta, eta > 0, eta < 10_000_000 else { return nil }
        return eta
    }

    var downSpeed: Int64 { rateDownload ?? 0 }
    var upSpeed: Int64 { rateUpload ?? 0 }

    // MARK: Errors

    /// Global error string overlaid with per-tracker announce failures
    /// (tracker errors are suppressed once any tracker announces OK).
    var effectiveError: String? {
        var trackerError: String?
        if let stats = trackerStats, !stats.isEmpty {
            var anyOk = false
            var lastError: String?
            for st in stats where st.hasAnnounced == true {
                if st.lastAnnounceSucceeded == true {
                    anyOk = true
                } else if let r = st.lastAnnounceResult, !r.isEmpty, r != "Success" {
                    lastError = r
                }
            }
            if !anyOk {
                trackerError = lastError
            }
        }

        let global = (errorString ?? "").isEmpty ? nil : errorString
        if let global {
            if let trackerError, trackerError == global {
                return trackerError
            }
            return global
        }
        return trackerError
    }

    var hasError: Bool {
        effectiveError != nil
    }

    /// Whether the global daemon error (not just a tracker warning) is set.
    var hasGlobalError: Bool {
        !(errorString ?? "").isEmpty
    }

    // MARK: Seeds/peers columns

    /// `connected/total` (or just `connected` when the tracker reports no total).
    var seedsText: String {
        let connected = peersSendingToUs ?? 0
        if let total = trackerStats?.first?.seederCount, total >= 0 {
            return "\(connected)/\(total)"
        }
        return "\(connected)"
    }

    var seedsSort: Int {
        if let total = trackerStats?.first?.seederCount, total >= 0 {
            return total
        }
        return peersSendingToUs ?? 0
    }

    var peersText: String {
        let connected = peersGettingFromUs ?? 0
        if let total = trackerStats?.first?.leecherCount, total >= 0 {
            if connected > total {
                return "\(connected)/\(total) (other peers)"
            }
            return "\(connected)/\(total)"
        }
        return "\(connected)"
    }

    var peersSort: Int {
        if let total = trackerStats?.first?.leecherCount, total >= 0 {
            return total
        }
        return peersGettingFromUs ?? 0
    }

    // MARK: Derived display values (used as table sort keys)

    var labelsText: String {
        (labels ?? []).joined(separator: ", ")
    }

    var trackerHost: String {
        TrackerGroups.host(from: trackerStats?.first?.announce ?? trackers?.first?.announce)
    }

    var trackerStatusText: String {
        guard let first = trackerStats?.first else { return "-" }
        if first.announceState == 2 || first.announceState == 3 {
            return "Updating"
        }
        if first.hasAnnounced == true {
            if first.lastAnnounceSucceeded == true { return "Working" }
            let r = first.lastAnnounceResult ?? ""
            return r == "Success" ? "Working" : (r.isEmpty ? "-" : r)
        }
        return "-"
    }

    var priorityText: String {
        switch bandwidthPriority ?? 0 {
        case 1: "High"
        case -1: "Low"
        default: "Normal"
        }
    }

    /// `wanted` entry for a file index (0 = not downloaded).
    func isWanted(_ index: Int) -> Bool {
        guard let wanted, index < wanted.count else { return true }
        return wanted[index] != 0
    }

    /// `priorities` entry for a file index (-1000 skip, -1 low, 0 normal, 1 high).
    func filePriority(_ index: Int) -> Int {
        guard let priorities, index < priorities.count else { return 0 }
        return priorities[index]
    }

    var ratioForSort: Double {
        guard let r = uploadRatio else { return -1 }
        if r.isNaN { return -1 }
        if r.isInfinite { return Double.greatestFiniteMagnitude }
        return r
    }

    var etaForSort: Int {
        effectiveEta ?? Int.max
    }
}

// MARK: - Status filters

public enum FilterID: String, CaseIterable, Identifiable, Sendable {
    case all
    case downloading
    case completed
    case active
    case inactive
    case stopped
    case error
    case waiting

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All torrents"
        case .downloading: "Downloading"
        case .completed: "Completed"
        case .active: "Active"
        case .inactive: "Inactive"
        case .stopped: "Stopped"
        case .error: "Error"
        case .waiting: "Waiting"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .downloading: "arrow.down.circle.fill"
        case .completed: "checkmark.circle"
        case .active: "bolt.fill"
        case .inactive: "moon.zzz.fill"
        case .stopped: "pause.circle"
        case .error: "exclamationmark.triangle.fill"
        case .waiting: "clock.fill"
        }
    }

    public func matches(_ t: Torrent) -> Bool {
        switch self {
        case .all:
            return true
        case .downloading:
            return t.statusValue == .downloading
        case .completed:
            return t.displayStatus == .seeding || t.isFinishedState
        case .active:
            return t.isActive
        case .inactive:
            return !t.isActive && !t.isStopped
        case .stopped:
            return t.isStopped
        case .error:
            return t.hasError
        case .waiting:
            // Matches the reference app: queued check + queued download are
            // "waiting"; verifying shows as Verifying in the Status column but
            // still counts here.
            switch t.statusValue {
            case .checkWait, .checking, .downloadWait:
                return true
            default:
                return false
            }
        }
    }
}

/// A selected sidebar entry: a status filter or one of the groupings.
public enum FilterSelection: Hashable, Sendable {
    case status(FilterID)
    case folder(String)
    case label(String)
    case tracker(String)
}

public struct GroupOption: Identifiable, Hashable, Sendable {
    public let selection: FilterSelection
    public let title: String
    public let count: Int
    public let systemImage: String
    /// Full download directory path for folder groups (shown as tooltip).
    public let detail: String?

    public var id: FilterSelection { selection }

    public init(
        selection: FilterSelection,
        title: String,
        count: Int,
        systemImage: String,
        detail: String? = nil
    ) {
        self.selection = selection
        self.title = title
        self.count = count
        self.systemImage = systemImage
        self.detail = detail
    }
}

public struct FilterCounts: Sendable {
    public var values: [FilterID: Int]

    public init(torrents: [Torrent]) {
        var counts = [FilterID: Int]()
        for id in FilterID.allCases {
            counts[id] = 0
        }
        for t in torrents {
            for id in FilterID.allCases where id.matches(t) {
                counts[id, default: 0] += 1
            }
        }
        values = counts
    }

    public subscript(id: FilterID) -> Int {
        values[id] ?? 0
    }
}

// MARK: - Groupings

public enum TrackerGroups {
    /// Tracker host with scheme, port and `bt.`/`bt1.`..`bt9.` prefixes removed.
    public static func host(from announce: String?) -> String {
        guard var s = announce, !s.isEmpty else { return "No tracker" }
        if let r = s.range(of: "://") {
            s = String(s[r.upperBound...])
        }
        if let i = s.firstIndex(where: { $0 == "/" || $0 == "?" }) {
            s = String(s[..<i])
        }
        if let i = s.lastIndex(of: ":") {
            s = String(s[..<i])
        }
        let lower = s.lowercased()
        if lower.hasPrefix("bt.") {
            s = String(s.dropFirst(3))
        } else if lower.hasPrefix("bt"), lower.count > 3, lower.dropFirst(2).first?.isNumber == true,
            let dotIndex = s.firstIndex(of: ".")
        {
            // bt1.example.com .. bt9.example.com
            s = String(s[s.index(after: dotIndex)...])
        }
        return s.isEmpty ? "No tracker" : s
    }
}

public enum Groupings {
    public static func folders(_ torrents: [Torrent]) -> [GroupOption] {
        var byPath = [String: Int]()
        for t in torrents {
            if let dir = t.downloadDir, !dir.isEmpty {
                byPath[dir, default: 0] += 1
            }
        }
        return byPath
            .sorted { $0.key < $1.key }
            .map { path, count in
                let base = (path as NSString).lastPathComponent
                return GroupOption(
                    selection: .folder(path),
                    title: base.isEmpty ? path : base,
                    count: count,
                    systemImage: "folder",
                    detail: path
                )
            }
    }

    public static func labels(_ torrents: [Torrent]) -> [GroupOption] {
        var byLabel = [String: Int]()
        for t in torrents {
            for label in t.labels ?? [] where !label.isEmpty {
                byLabel[label, default: 0] += 1
            }
        }
        return byLabel
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { label, count in
                GroupOption(
                    selection: .label(label),
                    title: label,
                    count: count,
                    systemImage: "tag"
                )
            }
    }

    public static func trackers(_ torrents: [Torrent]) -> [GroupOption] {
        var byHost = [String: Int]()
        for t in torrents {
            let host = TrackerGroups.host(
                from: t.trackerStats?.first?.announce ?? t.trackers?.first?.announce
            )
            byHost[host, default: 0] += 1
        }
        return byHost
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { host, count in
                GroupOption(
                    selection: .tracker(host),
                    title: host,
                    count: count,
                    systemImage: "globe"
                )
            }
    }
}

// MARK: - Matching a selection against a torrent

public extension FilterSelection {
    func matches(_ t: Torrent) -> Bool {
        switch self {
        case .status(let id):
            return id.matches(t)
        case .folder(let path):
            return t.downloadDir == path
        case .label(let label):
            return (t.labels ?? []).contains(label)
        case .tracker(let host):
            let tHost = TrackerGroups.host(
                from: t.trackerStats?.first?.announce ?? t.trackers?.first?.announce
            )
            return tHost == host
        }
    }
}
