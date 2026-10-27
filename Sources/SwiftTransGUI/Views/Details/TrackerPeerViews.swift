import SwiftUI
import TransGUICore

// MARK: - Trackers tab

/// One tracker row: a `trackers` entry merged positionally with `trackerStats`.
private struct TrackerRow: Identifiable {
    let id: Int
    let name: String
    let status: String
    let updateIn: String
    /// `nil` renders a blank cell (seeder count unknown).
    let seeds: String?
    /// Sort key for `Update in`: 0 = announcing now, seconds until the next
    /// announce, greatest = no countdown (`-`).
    let updateInSort: Double
    /// Sort key for `Seeds` (unknown sorts as -1).
    let seedsSort: Int
}

/// Trackers tab: Name / Status / Update in / Seeds.
struct TrackersDetailsView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder: [KeyPathComparator<TrackerRow>] = []

    var body: some View {
        if let trackers = model.details?.trackers {
            Table(sorted(rows(for: trackers)), sortOrder: $sortOrder) {
                TableColumn("Name", value: \TrackerRow.name) { row in
                    Text(row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(row.name)
                }
                .width(min: 200, ideal: 340)

                TableColumn("Status", value: \TrackerRow.status) { row in
                    Text(row.status)
                        .foregroundStyle(row.status.isEmpty ? Color.secondary : Color.primary)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Update in", value: \TrackerRow.updateInSort) { row in
                    cellText(row.updateIn, align: .trailing)
                }
                .width(min: 80, ideal: 90)

                TableColumn("Seeds", value: \TrackerRow.seedsSort) { row in
                    cellText(row.seeds, align: .trailing)
                }
                .width(min: 50, ideal: 60)
            }
        } else {
            DetailsStatusView()
        }
    }

    private func sorted(_ rows: [TrackerRow]) -> [TrackerRow] {
        guard !sortOrder.isEmpty else { return rows }
        return rows.sorted(using: sortOrder)
    }

    private func rows(for trackers: [Tracker]) -> [TrackerRow] {
        let stats = model.details?.trackerStats ?? []
        let id = model.selection.sorted().first
        let listRow = model.torrents.first { $0.id == id }
        // Stopped/finished torrents do not announce: no status or seeds.
        let noInfo = listRow?.isStopped == true || listRow?.isFinishedState == true
        let now = Date().timeIntervalSince1970

        return trackers.enumerated().map { index, tracker in
            let stat = index < stats.count ? stats[index] : nil
            var status = ""
            var update: Double = 0
            var updateSort: Double = .greatestFiniteMagnitude
            var seeds: Int?
            if !noInfo, let stat {
                if stat.announceState == 2 || stat.announceState == 3 {
                    status = "Updating"
                    update = 1
                    updateSort = 0
                } else {
                    if stat.hasAnnounced == true {
                        let result = stat.lastAnnounceResult ?? ""
                        if stat.lastAnnounceSucceeded == true || result == "Success" {
                            status = "Working"
                        } else if !result.isEmpty {
                            status = result
                        }
                    }
                    update = stat.nextAnnounceTime ?? 0
                    if update > 1 {
                        updateSort = max(0, update - now)
                    }
                }
                seeds = stat.seederCount
            }
            return TrackerRow(
                id: tracker.id ?? index,
                name: tracker.announce ?? "-",
                status: status,
                updateIn: updateText(update, now: now),
                seeds: seeds.flatMap { $0 >= 0 ? "\($0)" : nil },
                updateInSort: updateSort,
                seedsSort: seeds ?? -1
            )
        }
    }

    /// `-` when there is no countdown, `Updating...` while announcing,
    /// otherwise the time left until the next announce.
    private func updateText(_ value: Double, now: TimeInterval) -> String {
        if value == 1 {
            return "Updating..."
        }
        guard value > 1 else { return "-" }
        let seconds = Int(value - now)
        guard seconds > 0 else { return "-" }
        return Fmt.eta(seconds) ?? "-"
    }

    private func cellText(_ text: String?, align: HorizontalAlignment) -> some View {
        HStack {
            if align == .trailing { Spacer(minLength: 0) }
            Text(text ?? "")
                .monospacedDigit()
                .foregroundStyle(text == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if align == .leading { Spacer(minLength: 0) }
        }
    }
}

// MARK: - Peers tab

/// One row of the peers table.
private struct PeerRow: Identifiable {
    /// `address:port` (unique per peer).
    let id: String
    let host: String
    let port: Int
    let client: String
    let flags: String
    let have: String
    let upSpeed: Int64
    let downSpeed: Int64
    /// Sort key for `Have` (0...1 progress).
    let haveSort: Double
}

/// Peers tab: Host / Port / Client / Flags / Have / Up speed / Down speed.
struct PeersDetailsView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder: [KeyPathComparator<PeerRow>] = []

    var body: some View {
        if let peers = model.details?.peers {
            if peers.isEmpty {
                Text("No connected peers.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let rows = sorted(peers.map(row))
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Host", value: \PeerRow.host) { peer in
                        Text(peer.host)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .width(min: 120, ideal: 160)

                    TableColumn("Port", value: \PeerRow.port) { peer in
                        cellText("\(peer.port)", align: .trailing)
                    }
                    .width(min: 50, ideal: 60)

                    TableColumn("Client", value: \PeerRow.client) { peer in
                        Text(peer.client)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(peer.client)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Flags", value: \PeerRow.flags) { peer in
                        Text(peer.flags)
                            .monospaced()
                    }
                    .width(min: 50, ideal: 70)

                    TableColumn("Have", value: \PeerRow.haveSort) { peer in
                        cellText(peer.have, align: .trailing)
                    }
                    .width(min: 55, ideal: 65)

                    TableColumn("Up speed", value: \PeerRow.upSpeed) { peer in
                        cellText(Fmt.speed(peer.upSpeed), align: .trailing)
                    }
                    .width(min: 70, ideal: 85)

                    TableColumn("Down speed", value: \PeerRow.downSpeed) { peer in
                        cellText(Fmt.speed(peer.downSpeed), align: .trailing)
                    }
                    .width(min: 70, ideal: 85)
                }
            }
        } else {
            DetailsStatusView()
        }
    }

    private func sorted(_ rows: [PeerRow]) -> [PeerRow] {
        guard !sortOrder.isEmpty else { return rows }
        return rows.sorted(using: sortOrder)
    }

    private func row(_ peer: Peer) -> PeerRow {
        let progress = max(0, min(1, peer.progress ?? 0))
        return PeerRow(
            id: "\(peer.address ?? "?"):\(peer.port ?? 0)",
            host: peer.address ?? "-",
            port: peer.port ?? 0,
            client: peer.clientName ?? "-",
            flags: peer.flagStr ?? "",
            have: String(format: "%.1f%%", progress * 100),
            upSpeed: peer.rateToPeer ?? 0,
            downSpeed: peer.rateToClient ?? 0,
            haveSort: progress
        )
    }

    private func cellText(_ text: String?, align: HorizontalAlignment) -> some View {
        HStack {
            if align == .trailing { Spacer(minLength: 0) }
            Text(text ?? "")
                .monospacedDigit()
                .foregroundStyle(text == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if align == .leading { Spacer(minLength: 0) }
        }
    }
}
