import Foundation

// MARK: - Torrent list request fields

/// Fields requested for the main torrent list (mirrors what the UI needs).
public enum TorrentListFields {
    public static let all: [String] = [
        "id", "name", "status", "errorString",
        "sizeWhenDone", "leftUntilDone", "totalSize",
        "rateDownload", "rateUpload", "eta", "uploadRatio",
        "downloadedEver", "uploadedEver",
        "addedDate", "doneDate", "activityDate",
        "queuePosition", "bandwidthPriority", "secondsSeeding",
        "isPrivate", "labels", "downloadDir",
        "peersSendingToUs", "peersGettingFromUs",
        "trackerStats", "metadataPercentComplete", "recheckProgress",
        "isFinished",
    ]
}

// MARK: - Details pane request fields

/// Field sets for the bottom details pane (`torrent-get` with `ids: [selectedId]`).
public enum DetailsFields {
    /// General tab: everything the reference app's FillGeneralInfo reads.
    public static let general: [String] = [
        "id", "name", "status", "errorString",
        "totalSize", "sizeWhenDone", "leftUntilDone",
        "pieceCount", "pieceSize", "haveValid", "comment",
        "downloadedEver", "uploadedEver", "corruptEver",
        "downloadLimited", "downloadLimit", "uploadLimited", "uploadLimit",
        "maxConnectedPeers", "nextAnnounceTime", "eta",
        "peersSendingToUs", "peersGettingFromUs", "uploadRatio",
        "addedDate", "doneDate", "activityDate", "downloadDir",
        "trackerStats", "secondsDownloading", "secondsSeeding",
        "isPrivate", "labels", "magnetLink", "metadataPercentComplete",
        "hashString", "creator", "dateCreated", "recheckProgress",
    ]

    /// Piece availability bitfield (base64 string at RPC >= 5); fetched
    /// throttled alongside `.general`.
    public static let pieces = "pieces"

    /// Trackers tab: `trackers` merged positionally with `trackerStats`.
    public static let trackers: [String] = [
        "id", "trackers", "trackerStats", "nextAnnounceTime",
    ]

    /// Peers tab.
    public static let peers: [String] = ["id", "peers"]

    /// Files tab: file list with per-file priorities and wanted flags.
    public static let files: [String] = [
        "id", "files", "priorities", "wanted", "downloadDir",
    ]
}

/// Fields fetched for a torrent right after `torrent-add` (add dialog input).
public enum AddTorrentFields {
    public static let all: [String] = [
        "id", "name", "files", "maxConnectedPeers", "metadataPercentComplete",
    ]
}

/// Fields fetched by the "Torrent properties" dialog (General + Advanced).
public enum PropertiesFields {
    public static let all: [String] = [
        "id", "name",
        "downloadLimit", "downloadLimited", "uploadLimit", "uploadLimited",
        "maxConnectedPeers",
        "seedRatioMode", "seedRatioLimit", "seedIdleMode", "seedIdleLimit",
        "trackers",
    ]
}

// MARK: - Request arguments

/// Empty argument/response object: encodes as `{}` and decodes the daemon's
/// empty `arguments` (e.g. `torrent-set` replies).
public struct EmptyArguments: Codable, Sendable {}

public struct TorrentGetArgs: Encodable, Sendable {
    public let fields: [String]
    public let ids: [Int]?

    public init(fields: [String], ids: [Int]? = nil) {
        self.fields = fields
        self.ids = ids
    }
}

/// Flat `trackerReplace` pairs for `torrent-set`: alternating tracker id and
/// new announce URL (`[id, url, id, url, ...]` — the Transmission 3 wire
/// format, verified against the reference app's request builder).
public struct TrackerReplacePairs: Encodable, Sendable {
    public let pairs: [(id: Int, url: String)]

    public init(pairs: [(id: Int, url: String)]) {
        self.pairs = pairs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for pair in pairs {
            try container.encode(pair.id)
            try container.encode(pair.url)
        }
    }
}

/// Arguments for `torrent-set`: file selection/priority, bandwidth and
/// seeding limits, labels and tracker edits. `nil` (unset) fields are
/// omitted from the JSON, so only the keys the daemon needs are sent.
public struct TorrentSetArgs: Encodable, Sendable {
    public let ids: [Int]
    public var filesWanted: [Int]?
    public var filesUnwanted: [Int]?
    public var priorityHigh: [Int]?
    public var priorityNormal: [Int]?
    public var priorityLow: [Int]?
    /// Per-torrent peer limit (`peer-limit`), applied by the add dialog.
    public var peerLimit: Int?
    /// Bandwidth priority (-1 low, 0 normal, 1 high).
    public var bandwidthPriority: Int?
    /// Torrent labels (RPC 16+), replaced wholesale.
    public var labels: [String]?
    public var downloadLimited: Bool?
    public var downloadLimit: Int?
    public var uploadLimited: Bool?
    public var uploadLimit: Int?
    /// Seed ratio mode: 0 follow global, 1 stop at limit, 2 unlimited.
    public var seedRatioMode: Int?
    public var seedRatioLimit: Double?
    /// Seed idle mode: 0 follow global, 1 stop after idle, 2 unlimited.
    public var seedIdleMode: Int?
    public var seedIdleLimit: Int?
    /// Tracker edits (camelCase RPC keys).
    public var trackerAdd: [String]?
    public var trackerRemove: [Int]?
    public var trackerReplace: TrackerReplacePairs?

    public init(ids: [Int]) {
        self.ids = ids
    }

    enum CodingKeys: String, CodingKey {
        case ids
        case filesWanted = "files-wanted"
        case filesUnwanted = "files-unwanted"
        case priorityHigh = "priority-high"
        case priorityNormal = "priority-normal"
        case priorityLow = "priority-low"
        case peerLimit = "peer-limit"
        case bandwidthPriority, labels
        case downloadLimited, downloadLimit, uploadLimited, uploadLimit
        case seedRatioMode, seedRatioLimit, seedIdleMode, seedIdleLimit
        case trackerAdd, trackerRemove, trackerReplace
    }
}

public struct FreeSpaceArgs: Encodable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

/// Arguments for `torrent-add`: either `metainfo` (base64-encoded .torrent
/// contents) or `filename` (a URL or magnet link the daemon fetches itself).
public struct TorrentAddArgs: Encodable, Sendable {
    public let paused: Bool
    public var filename: String?
    public var metainfo: String?
    public var downloadDir: String?
    public var peerLimit: Int?

    public init(
        paused: Bool,
        filename: String? = nil,
        metainfo: String? = nil,
        downloadDir: String? = nil,
        peerLimit: Int? = nil
    ) {
        self.paused = paused
        self.filename = filename
        self.metainfo = metainfo
        self.downloadDir = downloadDir
        self.peerLimit = peerLimit
    }

    enum CodingKeys: String, CodingKey {
        case paused, filename, metainfo
        case downloadDir = "download-dir"
        case peerLimit = "peer-limit"
    }
}

/// Arguments for `torrent-remove`; local data is kept unless asked otherwise.
public struct TorrentRemoveArgs: Encodable, Sendable {
    public let ids: [Int]
    public var deleteLocalData: Bool

    public init(ids: [Int], deleteLocalData: Bool = false) {
        self.ids = ids
        self.deleteLocalData = deleteLocalData
    }

    enum CodingKeys: String, CodingKey {
        case ids
        case deleteLocalData = "delete-local-data"
    }
}

/// Arguments for `torrent-rename-path` (RPC >= 15): renames `path`
/// (for the torrent root, the torrent's name) to `name`.
public struct TorrentRenamePathArgs: Encodable, Sendable {
    public let ids: [Int]
    public let path: String
    public let name: String

    public init(ids: [Int], path: String, name: String) {
        self.ids = ids
        self.path = path
        self.name = name
    }
}

/// Bare `ids` arguments (`torrent-start`, `torrent-stop`, ...).
public struct TorrentIdsArgs: Encodable, Sendable {
    public let ids: [Int]

    public init(ids: [Int]) {
        self.ids = ids
    }
}

/// `ids` arguments for torrent actions where omitting `ids` applies the
/// action to every torrent (`torrent-start`/`torrent-stop` without ids).
public struct TorrentActionArgs: Encodable, Sendable {
    public let ids: [Int]?

    public init(ids: [Int]? = nil) {
        self.ids = ids
    }
}

/// Arguments for `torrent-set-location` (RPC >= 6): move or search for the
/// torrent's data at `location`.
public struct TorrentSetLocationArgs: Encodable, Sendable {
    public let ids: [Int]
    public let location: String
    public let move: Bool

    public init(ids: [Int], location: String, move: Bool) {
        self.ids = ids
        self.location = location
        self.move = move
    }
}

/// Argument for `session-set` toggling alternate (turtle) bandwidth limits.
public struct SessionAltSpeedArgs: Encodable, Sendable {
    public let altSpeedEnabled: Bool

    public init(altSpeedEnabled: Bool) {
        self.altSpeedEnabled = altSpeedEnabled
    }

    enum CodingKeys: String, CodingKey {
        case altSpeedEnabled = "alt-speed-enabled"
    }
}

/// Arguments for `session-set` (Transmission options dialog, status-bar
/// speed limits). Every key is optional: `nil` (unset) fields are omitted
/// from the JSON, so callers send only the values they actually change.
public struct SessionSetArgs: Encodable, Sendable {
    public init() {}

    public var downloadDir: String?
    public var renamePartialFiles: Bool?
    public var incompleteDirEnabled: Bool?
    public var incompleteDir: String?
    public var seedRatioLimited: Bool?
    public var seedRatioLimit: Double?
    public var idleSeedingLimitEnabled: Bool?
    public var idleSeedingLimit: Int?
    public var cacheSizeMb: Int?

    public var peerPort: Int?
    public var peerPortRandomOnStart: Bool?
    public var portForwardingEnabled: Bool?
    public var encryption: String?
    public var peerLimitGlobal: Int?
    public var pexEnabled: Bool?
    public var dhtEnabled: Bool?
    public var lpdEnabled: Bool?
    public var utpEnabled: Bool?
    public var blocklistEnabled: Bool?
    public var blocklistUrl: String?

    public var speedLimitDownEnabled: Bool?
    public var speedLimitDown: Int?
    public var speedLimitUpEnabled: Bool?
    public var speedLimitUp: Int?
    public var altSpeedEnabled: Bool?
    public var altSpeedDown: Int?
    public var altSpeedUp: Int?
    public var altSpeedTimeEnabled: Bool?
    public var altSpeedTimeBegin: Int?
    public var altSpeedTimeEnd: Int?
    public var altSpeedTimeDay: Int?

    public var downloadQueueEnabled: Bool?
    public var downloadQueueSize: Int?
    public var seedQueueEnabled: Bool?
    public var seedQueueSize: Int?
    public var queueStalledEnabled: Bool?
    public var queueStalledMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case downloadDir = "download-dir"
        case renamePartialFiles = "rename-partial-files"
        case incompleteDirEnabled = "incomplete-dir-enabled"
        case incompleteDir = "incomplete-dir"
        case seedRatioLimited = "seed-ratio-limited"
        case seedRatioLimit = "seed-ratio-limit"
        case idleSeedingLimitEnabled = "idle-seeding-limit-enabled"
        case idleSeedingLimit = "idle-seeding-limit"
        case cacheSizeMb = "cache-size-mb"
        case peerPort = "peer-port"
        case peerPortRandomOnStart = "peer-port-random-on-start"
        case portForwardingEnabled = "port-forwarding-enabled"
        case encryption
        case peerLimitGlobal = "peer-limit-global"
        case pexEnabled = "pex-enabled"
        case dhtEnabled = "dht-enabled"
        case lpdEnabled = "lpd-enabled"
        case utpEnabled = "utp-enabled"
        case blocklistEnabled = "blocklist-enabled"
        case blocklistUrl = "blocklist-url"
        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitDown = "speed-limit-down"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case speedLimitUp = "speed-limit-up"
        case altSpeedEnabled = "alt-speed-enabled"
        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case altSpeedTimeEnabled = "alt-speed-time-enabled"
        case altSpeedTimeBegin = "alt-speed-time-begin"
        case altSpeedTimeEnd = "alt-speed-time-end"
        case altSpeedTimeDay = "alt-speed-time-day"
        case downloadQueueEnabled = "download-queue-enabled"
        case downloadQueueSize = "download-queue-size"
        case seedQueueEnabled = "seed-queue-enabled"
        case seedQueueSize = "seed-queue-size"
        case queueStalledEnabled = "queue-stalled-enabled"
        case queueStalledMinutes = "queue-stalled-minutes"
    }
}

/// `blocklist-update` response arguments (`blocklist-size` = rule count).
public struct BlocklistUpdateResponse: Codable, Sendable, Equatable {
    public let blocklistSize: Int?

    enum CodingKeys: String, CodingKey {
        case blocklistSize = "blocklist-size"
    }
}

/// `trackerAdd` argument for `torrent-set` (the RPC key is camelCase here).
public struct TrackerAddArgs: Encodable, Sendable {
    public let ids: [Int]
    public let trackerAdd: [String]

    public init(ids: [Int], trackerAdd: [String]) {
        self.ids = ids
        self.trackerAdd = trackerAdd
    }
}

// MARK: - Response models

public struct TrackerStat: Codable, Sendable, Equatable {
    public let id: Int?
    public let announce: String?
    public let hasAnnounced: Bool?
    public let announceState: Int?
    public let lastAnnounceSucceeded: Bool?
    public let lastAnnounceResult: String?
    public let nextAnnounceTime: Double?
    public let seederCount: Int?
    public let leecherCount: Int?
    public let downloadCount: Int?
    public let lastAnnouncePeerCount: Int?
    public let isBackup: Bool?
}

public struct Tracker: Codable, Sendable, Equatable {
    public let id: Int?
    public let announce: String?
    public let scrape: String?
    public let tier: Int?
}

public struct TorrentFile: Codable, Sendable, Equatable {
    public let name: String?
    public let length: Int64?
    public let bytesCompleted: Int64?
}

public struct Peer: Codable, Sendable, Equatable {
    public let address: String?
    public let port: Int?
    public let clientName: String?
    public let flagStr: String?
    public let progress: Double?
    public let rateToClient: Int64?
    public let rateToPeer: Int64?
}

public struct Torrent: Codable, Sendable, Identifiable, Equatable {
    public let id: Int

    public let name: String?
    public let status: Int?
    public let errorString: String?

    public let sizeWhenDone: Int64?
    public let leftUntilDone: Int64?
    public let totalSize: Int64?
    public let rateDownload: Int64?
    public let rateUpload: Int64?
    public let eta: Int?
    public let uploadRatio: Double?

    public let downloadedEver: Int64?
    public let uploadedEver: Int64?
    public let corruptEver: Int64?

    public let addedDate: Double?
    public let doneDate: Double?
    public let activityDate: Double?
    public let queuePosition: Int?
    public let bandwidthPriority: Int?
    public let secondsSeeding: Int?
    public let secondsDownloading: Int?

    public let isPrivate: Bool?
    public let isFinished: Bool?
    public let labels: [String]?
    public let downloadDir: String?

    public let peersSendingToUs: Int?
    public let peersGettingFromUs: Int?
    public let trackerStats: [TrackerStat]?
    public let metadataPercentComplete: Double?
    public let recheckProgress: Double?

    public let magnetLink: String?
    public let hashString: String?
    public let creator: String?
    public let dateCreated: Double?
    public let comment: String?

    public let pieceCount: Int?
    public let pieceSize: Int64?
    public let haveValid: Int64?
    /// Base64-encoded piece availability bitfield (each bit = one piece).
    public let pieces: String?

    public let files: [TorrentFile]?
    public let priorities: [Int]?
    /// 0/1 per file (the daemon sends numbers, not JSON booleans).
    public let wanted: [Int]?
    public let trackers: [Tracker]?
    public let peers: [Peer]?

    public let downloadLimited: Bool?
    public let downloadLimit: Int?
    public let uploadLimited: Bool?
    public let uploadLimit: Int?
    public let maxConnectedPeers: Int?
    public let nextAnnounceTime: Double?
    public let seedRatioMode: Int?
    public let seedRatioLimit: Double?
    public let seedIdleMode: Int?
    public let seedIdleLimit: Int?
    public let announceResponse: String?
}

public struct SessionInfo: Codable, Sendable, Equatable {
    public let version: String?
    public let rpcVersion: Int?
    public let rpcVersionMinimum: Int?
    public let downloadDir: String?

    public let speedLimitDownEnabled: Bool?
    public let speedLimitDown: Int?
    public let speedLimitUpEnabled: Bool?
    public let speedLimitUp: Int?

    public let altSpeedEnabled: Bool?
    public let altSpeedDown: Int?
    public let altSpeedUp: Int?
    public let altSpeedTimeEnabled: Bool?
    public let altSpeedTimeBegin: Int?
    public let altSpeedTimeEnd: Int?
    public let altSpeedTimeDay: Int?

    public let peerLimitGlobal: Int?
    public let peerPort: Int?
    public let peerPortRandomOnStart: Bool?
    public let pexEnabled: Bool?
    public let dhtEnabled: Bool?
    public let lpdEnabled: Bool?
    public let utpEnabled: Bool?
    public let encryption: String?
    public let portForwardingEnabled: Bool?

    public let blocklistEnabled: Bool?
    public let blocklistUrl: String?
    public let blocklistSize: Int?

    public let incompleteDirEnabled: Bool?
    public let incompleteDir: String?
    public let renamePartialFiles: Bool?
    public let cacheSizeMb: Int?

    public let seedRatioLimited: Bool?
    public let seedRatioLimit: Double?
    public let idleSeedingLimitEnabled: Bool?
    public let idleSeedingLimit: Int?

    public let downloadQueueEnabled: Bool?
    public let downloadQueueSize: Int?
    public let seedQueueEnabled: Bool?
    public let seedQueueSize: Int?
    public let queueStalledEnabled: Bool?
    public let queueStalledMinutes: Int?

    public let downloadDirFreeSpace: Int64?

    enum CodingKeys: String, CodingKey {
        case version
        case rpcVersion = "rpc-version"
        case rpcVersionMinimum = "rpc-version-minimum"
        case downloadDir = "download-dir"
        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitDown = "speed-limit-down"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case speedLimitUp = "speed-limit-up"
        case altSpeedEnabled = "alt-speed-enabled"
        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case altSpeedTimeEnabled = "alt-speed-time-enabled"
        case altSpeedTimeBegin = "alt-speed-time-begin"
        case altSpeedTimeEnd = "alt-speed-time-end"
        case altSpeedTimeDay = "alt-speed-time-day"
        case peerLimitGlobal = "peer-limit-global"
        case peerPort = "peer-port"
        case peerPortRandomOnStart = "peer-port-random-on-start"
        case pexEnabled = "pex-enabled"
        case dhtEnabled = "dht-enabled"
        case lpdEnabled = "lpd-enabled"
        case utpEnabled = "utp-enabled"
        case encryption
        case portForwardingEnabled = "port-forwarding-enabled"
        case blocklistEnabled = "blocklist-enabled"
        case blocklistUrl = "blocklist-url"
        case blocklistSize = "blocklist-size"
        case incompleteDirEnabled = "incomplete-dir-enabled"
        case incompleteDir = "incomplete-dir"
        case renamePartialFiles = "rename-partial-files"
        case cacheSizeMb = "cache-size-mb"
        case seedRatioLimited = "seed-ratio-limited"
        case seedRatioLimit = "seed-ratio-limit"
        case idleSeedingLimitEnabled = "idle-seeding-limit-enabled"
        case idleSeedingLimit = "idle-seeding-limit"
        case downloadQueueEnabled = "download-queue-enabled"
        case downloadQueueSize = "download-queue-size"
        case seedQueueEnabled = "seed-queue-enabled"
        case seedQueueSize = "seed-queue-size"
        case queueStalledEnabled = "queue-stalled-enabled"
        case queueStalledMinutes = "queue-stalled-minutes"
        case downloadDirFreeSpace = "download-dir-free-space"
    }
}

public struct TransferStats: Codable, Sendable, Equatable {
    public let downloadedBytes: Int64?
    public let uploadedBytes: Int64?
    public let filesAdded: Int?
    public let secondsActive: Int64?

    enum CodingKeys: String, CodingKey {
        case downloadedBytes, uploadedBytes, filesAdded, secondsActive
    }
}

public struct SessionStats: Codable, Sendable, Equatable {
    public let downloadSpeed: Int64?
    public let uploadSpeed: Int64?
    public let torrentCount: Int?
    public let activeTorrentCount: Int?
    public let pausedTorrentCount: Int?
    public let currentStats: TransferStats?
    public let cumulativeStats: TransferStats?

    enum CodingKeys: String, CodingKey {
        case downloadSpeed, uploadSpeed, torrentCount, activeTorrentCount,
             pausedTorrentCount
        case currentStats = "current-stats"
        case cumulativeStats = "cumulative-stats"
    }
}

public struct FreeSpace: Codable, Sendable, Equatable {
    public let path: String?
    public let sizeBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case path
        case sizeBytes = "size-bytes"
    }
}

/// `torrent-get` response wrapper: `{"arguments": {"torrents": [...]}}`.
public struct TorrentListResponse: Decodable, Sendable {
    public let torrents: [Torrent]
}

/// A torrent reference returned by `torrent-add` (inside `torrent-added` or
/// `torrent-duplicate`).
public struct AddedTorrent: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String?
    public let hashString: String?

    public init(id: Int, name: String? = nil, hashString: String? = nil) {
        self.id = id
        self.name = name
        self.hashString = hashString
    }
}

/// `torrent-add` response arguments: exactly one of `torrent-added` /
/// `torrent-duplicate` is present (`torrent-duplicate` when the infohash is
/// already in the list; the daemon leaves the existing torrent untouched).
public struct TorrentAddResponse: Decodable, Sendable {
    public let added: AddedTorrent?
    public let duplicate: AddedTorrent?

    enum CodingKeys: String, CodingKey {
        case added = "torrent-added"
        case duplicate = "torrent-duplicate"
    }
}

public struct PortTest: Codable, Sendable, Equatable {
    public let portIsOpen: Bool?

    enum CodingKeys: String, CodingKey {
        case portIsOpen = "port-is-open"
    }
}
