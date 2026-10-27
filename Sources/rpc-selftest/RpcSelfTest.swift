import Darwin
import Foundation
import TransGUICore

/// Headless connectivity check for the RPC core.
/// Usage: rpc-selftest <password> --host <host[:port]> [--user <name>]
///        [--path <rpc path>] [--ssl] [--sort-test]
///        [--add-test <torrent path>] [--actions-test] [--session-test]
///
/// There is no built-in server address: `--host` is required (the shipped
/// app default is empty and configured through the connections dialog).
@main
struct RpcSelfTest {
    static let usage = """
        usage: rpc-selftest <password> --host <host[:port]> [--user <name>] \
        [--path <rpc path>] [--ssl] [--sort-test] [--add-test <torrent path>] \
        [--actions-test] [--session-test]
        """

    static func main() async {
        let args = CommandLine.arguments

        var password: String?
        var host = ""
        var port = 9091
        var username = RpcEndpoint.default.username
        var path = RpcEndpoint.default.path
        var useSSL = false
        var addTestPath: String?
        var runActionsTest = false
        var runSessionTest = false
        var runSortTest = false

        var index = 1
        while index < args.count {
            let arg = args[index]
            func value() -> String {
                index += 1
                guard index < args.count else {
                    print(usage)
                    exit(2)
                }
                return args[index]
            }
            switch arg {
            case "--host":
                let raw = value()
                if let colon = raw.lastIndex(of: ":"), !raw.contains("]"),
                    let p = Int(raw[raw.index(after: colon)...])
                {
                    host = String(raw[..<colon])
                    port = p
                } else {
                    host = raw
                }
            case "--user":
                username = value()
            case "--path":
                path = value()
            case "--ssl":
                useSSL = true
            case "--add-test":
                addTestPath = value()
            case "--actions-test":
                runActionsTest = true
            case "--session-test":
                runSessionTest = true
            case "--sort-test":
                runSortTest = true
            default:
                if arg.hasPrefix("--") {
                    print("unknown option: \(arg)")
                    print(usage)
                    exit(2)
                }
                if password == nil {
                    password = arg
                } else {
                    print("unexpected argument: \(arg)")
                    print(usage)
                    exit(2)
                }
            }
            index += 1
        }

        guard let password else {
            print(usage)
            exit(2)
        }
        if !runFormatChecks() {
            exit(1)
        }
        guard !host.isEmpty else {
            print("error: no server address configured (pass --host host[:port]; the app ships with an empty default)")
            print(usage)
            exit(2)
        }

        if runSortTest {
            runSortTestChecks()
        }

        let endpoint = RpcEndpoint(
            name: "selftest",
            host: host,
            port: port,
            useSSL: useSSL,
            path: path,
            username: username
        )
        print("endpoint: \(endpoint.rpcURL?.absoluteString ?? "?")  user: \(endpoint.username)")

        let client = TransmissionClient(endpoint: endpoint, password: password)

        do {
            let session: SessionInfo = try await client.call(method: "session-get")
            print(
                "session-get: OK  version=\(session.version ?? "?")  rpc=\(session.rpcVersion ?? 0)  "
                    + "downloadDir=\(session.downloadDir ?? "?")"
            )

            let rows = try await client.getTorrents(fields: TorrentListFields.all)
            print("torrent-get: OK  torrents=\(rows.count)")
            for t in rows.prefix(5) {
                let pct = String(format: "%.1f%%", t.progressFraction * 100)
                print(
                    "  - \(t.displayName)  status=\(t.displayStatus.rawValue)  "
                        + "progress=\(pct)  down=\(Fmt.speed(t.downSpeed) ?? "-")  "
                        + "up=\(Fmt.speed(t.upSpeed) ?? "-")"
                )
            }

            if let dir = session.downloadDir {
                let fs: FreeSpace = try await client.call(
                    method: "free-space",
                    arguments: FreeSpaceArgs(path: dir)
                )
                print("free-space: OK  \(Fmt.size(fs.sizeBytes))")
            }

            if let first = rows.first {
                var fields = DetailsFields.general
                fields.append(DetailsFields.pieces)
                let general = try await client.getTorrentDetails(fields: fields, ids: [first.id])
                print(
                    "torrent-get details: OK  id=\(general.id)  "
                        + "pieces-b64=\(general.pieces?.count ?? 0) chars  "
                        + "pieceCount=\(general.pieceCount ?? -1)"
                )

                let files = try await client.getTorrentDetails(
                    fields: DetailsFields.files, ids: [first.id]
                )
                print(
                    "torrent-get files: OK  files=\(files.files?.count ?? 0)  "
                        + "priorities=\(files.priorities?.count ?? 0)  "
                        + "wanted=\(files.wanted?.count ?? 0)"
                )

                let peers = try await client.getTorrentDetails(
                    fields: DetailsFields.peers, ids: [first.id]
                )
                print("torrent-get peers: OK  peers=\(peers.peers?.count ?? 0)")
            }

            let sessionStats: SessionStats = try await client.call(method: "session-stats")
            print(
                "session-stats: OK  torrents=\(sessionStats.torrentCount ?? 0)  "
                    + "downloaded=\(Fmt.size(sessionStats.cumulativeStats?.downloadedBytes))"
            )

            let counts = FilterCounts(torrents: rows)
            for id in FilterID.allCases {
                print("filter \(id.title): \(counts[id])")
            }

            if let path = addTestPath {
                try await runAddTest(client: client, session: session, path: path)
            }

            if runActionsTest {
                try await ActionsTest.run(client: client, session: session)
            }

            if runSessionTest {
                try await SessionTest.run(client: client, original: session)
            }

            print("SELFTEST PASSED")
            exit(0)
        } catch {
            let message = (error as? RpcError)?.errorDescription ?? String(describing: error)
            print("SELFTEST FAILED: \(message)")
            exit(1)
        }
    }

    /// Add a torrent paused via metainfo, verify it appears in the list,
    /// then remove it again (without deleting local data) and verify the
    /// count is back to the initial value. Proves the full wire flow used
    /// by the GUI's add-torrent dialog.
    static func runAddTest(
        client: TransmissionClient,
        session: SessionInfo,
        path: String
    ) async throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw RpcError.encoding("add-test: torrent file is empty: \(path)")
        }
        print("add-test: read \(url.lastPathComponent)  \(data.count) bytes")

        if let meta = TorrentMeta.parse(metainfo: data) {
            print(
                "add-test: bencode OK  name=\(meta.name ?? "?")  "
                    + "infohash=\(meta.infoHashHex ?? "?")  trackers=\(meta.trackers.count)"
            )
        } else {
            print("add-test: bencode parse failed (not a .torrent file?)")
        }

        let before = try await client.getTorrents(fields: ["id", "name"])
        print("add-test: torrents before = \(before.count)")

        let args = TorrentAddArgs(
            paused: true,
            metainfo: data.base64EncodedString(),
            downloadDir: session.downloadDir
        )

        let addedId: Int
        do {
            let response: TorrentAddResponse = try await client.call(
                method: "torrent-add", arguments: args
            )
            if let added = response.added {
                print("add-test: torrent-added  id=\(added.id)  name=\(added.name ?? "?")")
                addedId = added.id
            } else if let duplicate = response.duplicate {
                print(
                    "add-test: torrent-duplicate  id=\(duplicate.id)  "
                        + "name=\(duplicate.name ?? "?")  (already in the list; nothing removed)"
                )
                print("add-test: PASSED (duplicate path)")
                return
            } else {
                throw RpcError.invalidResponse
            }
        } catch let error as RpcError where error == .server("duplicate torrent") {
            print("add-test: server reported 'duplicate torrent' (older daemon); nothing removed")
            print("add-test: PASSED (duplicate path)")
            return
        }

        let listed = try await client.getTorrents(fields: ["id", "name"], ids: [addedId])
        guard listed.count == 1 else {
            throw RpcError.server("add-test: added torrent \(addedId) not found in the list")
        }
        print("add-test: torrent-get by id OK  \(listed[0].displayName)")

        let _: EmptyArguments = try await client.call(
            method: "torrent-remove",
            arguments: TorrentRemoveArgs(ids: [addedId])
        )
        print("add-test: torrent-remove OK  id=\(addedId)  (local data untouched)")

        let after = try await client.getTorrents(fields: ["id", "name"])
        print("add-test: torrents after = \(after.count)  (initial \(before.count))")
        guard after.count == before.count else {
            throw RpcError.server(
                "add-test: torrent count changed: \(before.count) -> \(after.count)"
            )
        }
        print("add-test: PASSED")
    }

    /// Regression checks for the size/speed/ETA/ratio formatters (the unit
    /// label once ran one step ahead of the value — `7.1 GB` shown as TB).
    static func runFormatChecks() -> Bool {
        let cases: [(Int64, String)] = [
            (0, "0 b"),
            (512, "512 b"),
            (1024, "1.0 KB"),
            (1536, "1.5 KB"),
            (1_572_864, "1.5 MB"),
            (1_610_612_736, "1.5 GB"),
            (7_516_192_768, "7.0 GB"),
        ]
        var ok = true
        for (input, expected) in cases {
            let got = Fmt.size(input)
            if got != expected {
                print("format-check FAIL: size(\(input)) = \(got), expected \(expected)")
                ok = false
            }
        }
        if let speed = Fmt.speed(1_572_864), speed != "1.5 MB/s" {
            print("format-check FAIL: speed(1572864) = \(speed), expected 1.5 MB/s")
            ok = false
        }
        if Fmt.speed(0) != nil {
            print("format-check FAIL: speed(0) should be blank")
            ok = false
        }
        if Fmt.ratio(-1) != "" || Fmt.ratio(1.5) != "1.500" {
            print("format-check FAIL: ratio formatting")
            ok = false
        }
        if ok {
            print("format-check: PASSED")
        }
        return ok
    }

    static func runSortTestChecks() {
        let json = """
            [
              {"id":1,"name":"banana","status":4,"rateDownload":1024,"uploadRatio":1.5},
              {"id":2,"name":"apple","status":6,"rateDownload":0,"uploadRatio":0.5},
              {"id":3,"name":"cherry","status":0,"rateDownload":0,"uploadRatio":-1}
            ]
            """
        let decoded = try! JSONDecoder().decode([Torrent].self, from: Data(json.utf8))
        let byName = decoded.sorted(using: [SortDescriptor(\Torrent.displayName)])
        print("sort-test name: \(byName.map { $0.displayName }.joined(separator: ", "))")
        let byProgress = decoded.sorted(using: [SortDescriptor(\Torrent.progressFraction)])
        print(
            "sort-test progress: \(byProgress.map { $0.progressText }.joined(separator: ", "))"
        )
    }
}
