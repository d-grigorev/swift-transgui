import Foundation
import Testing
import TransGUICore

/// Filter counts, grouping construction and selection matching.
@Suite("Filters and groupings")
struct FilterTests {
    private func torrent(_ json: String) -> Torrent {
        try! JSONDecoder().decode(Torrent.self, from: Data(json.utf8))
    }

    @Test("Counts over a mixed torrent list")
    func counts() {
        let rows = [
            torrent(#"{"id":1,"status":4,"sizeWhenDone":100,"leftUntilDone":50,"rateDownload":10}"#),
            torrent(#"{"id":2,"status":6,"rateUpload":5}"#),
            torrent(#"{"id":3,"status":0,"sizeWhenDone":100,"leftUntilDone":0}"#),
            torrent(#"{"id":4,"status":0,"sizeWhenDone":100,"leftUntilDone":10}"#),
            torrent(#"{"id":5,"status":1}"#),
            torrent(#"{"id":6,"status":4,"errorString":"oops"}"#),
        ]
        let counts = FilterCounts(torrents: rows)
        #expect(counts[.all] == 6)
        #expect(counts[.downloading] == 2)  // id 1 and the error torrent 6
        #expect(counts[.completed] == 2)  // seeding 2 + finished 3
        #expect(counts[.active] == 2)  // id 1 (down) + id 2 (up)
        #expect(counts[.stopped] == 2)  // id 3 + id 4
        #expect(counts[.error] == 1)  // id 6
        #expect(counts[.waiting] == 1)  // id 5
        // Inactive = not active and not stopped: the waiting torrent and the
        // downloading-but-idle error torrent.
        #expect(counts[.inactive] == 2)
    }

    @Test("Group selections match download dir, labels and tracker host")
    func selections() {
        let t = torrent(
            """
            {"id":1,"status":6,"downloadDir":"/downloads/tv","labels":["tv"],
             "trackerStats":[{"announce":"https://bt1.tracker.example.com/ann"}]}
            """)
        #expect(FilterSelection.folder("/downloads/tv").matches(t))
        #expect(!FilterSelection.folder("/downloads/movies").matches(t))
        #expect(FilterSelection.label("tv").matches(t))
        #expect(!FilterSelection.label("music").matches(t))
        #expect(FilterSelection.tracker("tracker.example.com").matches(t))
        #expect(!FilterSelection.tracker("other.example.com").matches(t))
        #expect(FilterSelection.status(.completed).matches(t))
    }

    @Test("Folder grouping lists every download directory")
    func folderGroups() {
        let rows = [
            torrent(#"{"id":1,"downloadDir":"/a"}"#),
            torrent(#"{"id":2,"downloadDir":"/a"}"#),
            torrent(#"{"id":3,"downloadDir":"/b"}"#),
        ]
        let groups = Groupings.folders(rows)
        #expect(groups.count == 2)
        #expect(groups[0].title == "a")
        #expect(groups[0].count == 2)
        #expect(groups[0].detail == "/a")
        #expect(groups[1].title == "b")
    }

    @Test("Label and tracker groupings aggregate")
    func labelAndTrackerGroups() {
        let rows = [
            torrent(#"{"id":1,"labels":["tv"],"trackerStats":[{"announce":"https://x.example.com/a"}]}"#),
            torrent(#"{"id":2,"labels":["tv","hd"],"trackerStats":[{"announce":"https://x.example.com/b"}]}"#),
        ]
        let labels = Groupings.labels(rows)
        #expect(labels.count == 2)
        #expect(labels.first { $0.title == "tv" }?.count == 2)
        #expect(labels.first { $0.title == "hd" }?.count == 1)

        // Same host groups together.
        let trackers = Groupings.trackers(rows)
        #expect(trackers.count == 1)
        #expect(trackers[0].title == "x.example.com")
        #expect(trackers[0].count == 2)
    }
}

/// Tracker announce URL → display host derivation.
@Suite("Tracker host parsing")
struct TrackerHostTests {
    @Test("Scheme, port, path and bt-prefix are stripped")
    func hosts() {
        #expect(TrackerGroups.host(from: nil) == "No tracker")
        #expect(TrackerGroups.host(from: "") == "No tracker")
        #expect(
            TrackerGroups.host(from: "https://tracker.example.com:443/announce")
                == "tracker.example.com")
        #expect(
            TrackerGroups.host(from: "udp://tracker.opentrackr.org:1337/announce")
                == "tracker.opentrackr.org")
        #expect(TrackerGroups.host(from: "http://bt4.t-ru.org/ann") == "t-ru.org")
        #expect(TrackerGroups.host(from: "http://bt.tracker.net/ann") == "tracker.net")
        #expect(
            TrackerGroups.host(from: "https://bt7.dog.com/announce.php?x=1") == "dog.com")
    }
}

/// RPC endpoint defaults and URL building.
@Suite("RPC endpoint")
struct RpcEndpointTests {
    @Test("The shipped default has no server address")
    func emptyByDefault() {
        #expect(!RpcEndpoint.default.isConfigured)
        #expect(RpcEndpoint.default.host.isEmpty)
        // No credentials ship with the app either.
        #expect(RpcEndpoint.default.username.isEmpty)
        #expect(RpcEndpoint.default.rpcURL == nil)
    }

    @Test("Configured endpoints build their RPC URL")
    func urls() {
        let plain = RpcEndpoint(
            name: "t", host: "example.com", port: 9091, useSSL: false,
            path: "/transmission/rpc", username: "u")
        #expect(plain.isConfigured)
        #expect(plain.rpcURL?.absoluteString == "http://example.com:9091/transmission/rpc")

        let tls = RpcEndpoint(
            name: "t", host: "example.com", port: 443, useSSL: true, path: "", username: "u")
        #expect(tls.rpcURL?.scheme == "https")
        #expect(tls.rpcURL?.host == "example.com")
        // Empty path falls back to the Transmission default.
        #expect(tls.rpcURL?.path == "/transmission/rpc")

        #expect(plain.keychainAccount == "u@example.com:9091/transmission/rpc")
        #expect(plain.statusCaption(version: "4.0.0") == "Transmission 4.0.0 at example.com:9091")
    }
}
