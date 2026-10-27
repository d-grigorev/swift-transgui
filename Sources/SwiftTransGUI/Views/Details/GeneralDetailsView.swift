import SwiftUI
import TransGUICore

/// General tab: `Downloaded:` + piece bar strip on top, then the Transfer
/// and Torrent sections with `Field: value` rows in responsive grids.
struct GeneralDetailsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let torrent = model.details?.general {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    progressStrip(for: torrent)
                    section("Transfer") { transferGrid(for: torrent) }
                    section("Torrent") { torrentGrid(for: torrent) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            DetailsStatusView()
        }
    }

    // MARK: Top strip

    private func progressStrip(for torrent: Torrent) -> some View {
        HStack(spacing: 10) {
            Text("Downloaded:")
                .foregroundStyle(.secondary)
            PieceMapView(data: model.details?.pieces, pieceCount: torrent.pieceCount ?? 0)
                .frame(height: 12)
                .frame(maxWidth: .infinity)
            Text(torrent.progressText)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
        }
    }

    // MARK: Sections

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            content()
        }
    }

    private func transferGrid(for t: Torrent) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            field("Status", t.displayStatus.rawValue)
            field("Error", t.effectiveError ?? "-", error: t.effectiveError != nil)
            field("Remaining", remainingText(t))
            field("Downloaded", Fmt.size(t.downloadedEver))
            field("Uploaded", Fmt.size(t.uploadedEver))
            field("Wasted", wastedText(t))
            field("Download speed", downloadSpeedText(t))
            field("Upload speed", uploadSpeedText)
            field("Share ratio", shareRatioText(t))
            field("Down limit", limitText(limited: t.downloadLimited, kilobytes: t.downloadLimit))
            field("Up limit", limitText(limited: t.uploadLimited, kilobytes: t.uploadLimit))
            field("Seeds", seedsText(t))
            field("Peers", peersText(t))
            field("Max peers", "\(t.maxConnectedPeers ?? 0)")
            field("Tracker", t.trackerHost)
            field(
                "Tracker update on",
                trackerUpdate(for: t).text,
                help: trackerUpdate(for: t).help
            )
            field(
                "Last active",
                Fmt.relativeTime(unix: t.activityDate),
                help: Fmt.absolute(unix: t.activityDate)
            )
        }
    }

    private func torrentGrid(for t: Torrent) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            field("Name", fullName(t))
            field(
                "Created on",
                Fmt.relativeTime(unix: t.dateCreated) + creatorSuffix(t),
                help: Fmt.absolute(unix: t.dateCreated) + creatorSuffix(t)
            )
            field("Total size", totalSizeText(t))
            field("Pieces", piecesText(t))
            field("Hash", t.hashString ?? "-")
            field("Comment", commentText(t))
            field("Added on", Fmt.relativeTime(unix: t.addedDate), help: Fmt.absolute(unix: t.addedDate))
            field(
                "Completed on",
                Fmt.relativeTime(unix: t.doneDate),
                help: Fmt.absolute(unix: t.doneDate)
            )
            field("Magnet Link", t.magnetLink ?? "-", selectable: true)
            field("Labels", t.labelsText.isEmpty ? "-" : t.labelsText)
        }
    }

    // MARK: Field row

    @ViewBuilder
    private func field(
        _ title: String,
        _ value: String,
        error: Bool = false,
        help: String? = nil,
        selectable: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(title):")
            fieldValue(value, error: error, selectable: selectable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help ?? value)
    }

    @ViewBuilder
    private func fieldValue(_ value: String, error: Bool, selectable: Bool) -> some View {
        if selectable {
            Text(value)
                .foregroundStyle(error ? Color.red : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        } else {
            Text(value)
                .foregroundStyle(error ? Color.red : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: Values

    /// The list row for the selected torrent. The details field set does not
    /// include the live rates, so - like the reference app - they come from
    /// the main list row.
    private var listRow: Torrent? {
        guard let id = model.selection.sorted().first else { return nil }
        return model.torrents.first { $0.id == id }
    }

    private func remainingText(_ t: Torrent) -> String {
        let left = t.leftUntilDone ?? 0
        let seconds: Int?
        if let down = listRow?.downSpeed, down > 0, left > 0 {
            seconds = Int(left / down)
        } else {
            seconds = t.eta
        }
        let eta = Fmt.eta(seconds) ?? "-"
        return "\(eta) (\(Fmt.size(t.leftUntilDone)))"
    }

    private func wastedText(_ t: Torrent) -> String {
        let corrupt = t.corruptEver ?? 0
        let pieceSize = t.pieceSize ?? 0
        let hashfails = pieceSize > 0 ? corrupt / pieceSize : 0
        return "\(Fmt.size(corrupt)) (\(hashfails) hashfails)"
    }

    private func downloadSpeedText(_ t: Torrent) -> String {
        let down = listRow?.downSpeed ?? 0
        var text = Fmt.speed(down) ?? Fmt.size(0) + "/s"
        if let seconds = t.secondsDownloading, seconds > 0,
            let downloaded = t.downloadedEver, downloaded > 0
        {
            let average = downloaded / Int64(seconds)
            text += " (average: \(Fmt.size(average))/s)"
        }
        return text
    }

    private var uploadSpeedText: String {
        Fmt.speed(listRow?.upSpeed ?? 0) ?? Fmt.size(0) + "/s"
    }

    private func shareRatioText(_ t: Torrent) -> String {
        var text = Fmt.ratio(t.uploadRatio)
        if text.isEmpty {
            text = "-"
        }
        if let seeding = t.secondsSeeding, seeding > 0 {
            text += " (\(Fmt.duration(Int64(seeding))))"
        }
        return text
    }

    private func limitText(limited: Bool?, kilobytes: Int?) -> String {
        guard limited == true else { return "-" }
        guard let kilobytes, kilobytes >= 0 else { return "∞" }
        return Fmt.size(Int64(kilobytes) * 1024) + "/s"
    }

    private func seedsText(_ t: Torrent) -> String {
        let connected = t.peersSendingToUs ?? 0
        let total = t.trackerStats?.first?.seederCount ?? -1
        if total >= 0 {
            return "\(connected) of \(total) connected"
        }
        return "\(connected) connected"
    }

    private func peersText(_ t: Torrent) -> String {
        let connected = t.peersGettingFromUs ?? 0
        let total = t.trackerStats?.first?.leecherCount ?? -1
        if total >= 0 {
            return "\(connected) connected of \(total) in swarm"
        }
        return "\(connected) connected"
    }

    private func trackerUpdate(for t: Torrent) -> (text: String, help: String) {
        let next: Double
        if let stat = t.trackerStats?.first {
            if stat.announceState == 2 || stat.announceState == 3 {
                return ("Updating...", Fmt.absolute(unix: stat.nextAnnounceTime))
            }
            next = stat.nextAnnounceTime ?? 0
        } else {
            next = t.nextAnnounceTime ?? 0
        }
        guard next > 0 else { return ("-", "-") }
        return (Fmt.relativeTime(unix: next), Fmt.absolute(unix: next))
    }

    private func fullName(_ t: Torrent) -> String {
        guard let dir = t.downloadDir, !dir.isEmpty else { return t.displayName }
        let base = dir.hasSuffix("/") ? dir : dir + "/"
        return base + t.displayName
    }

    private func creatorSuffix(_ t: Torrent) -> String {
        let creator = (t.creator ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return creator.isEmpty ? "" : " by \(creator)"
    }

    private func commentText(_ t: Torrent) -> String {
        let comment = (t.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return comment.isEmpty ? "-" : comment
    }

    private func totalSizeText(_ t: Torrent) -> String {
        guard let total = t.totalSize else { return "?" }
        let done = max(0, (t.sizeWhenDone ?? 0) - (t.leftUntilDone ?? 0))
        return "\(Fmt.size(total)) (\(Fmt.size(done)) done)"
    }

    private func piecesText(_ t: Torrent) -> String {
        guard let count = t.pieceCount, let size = t.pieceSize, size > 0 else { return "?" }
        let have: Int
        if t.totalSize == t.haveValid {
            have = count
        } else {
            have = Int((t.haveValid ?? 0) / size)
        }
        return "\(count) x \(Fmt.size(size)) (have \(have))"
    }
}

// MARK: - Piece availability bar

/// Slim bar drawn from the base64 `pieces` bitfield: one column per pixel of
/// width (aggregated), so torrents with huge piece counts stay cheap to draw.
struct PieceMapView: View {
    let data: Data?
    let pieceCount: Int

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }
            let bounds = CGRect(origin: .zero, size: size)
            let clip = Path(roundedRect: bounds, cornerRadius: 3)
            context.clip(to: clip)
            context.fill(clip, with: .color(.primary.opacity(0.08)))

            guard let data, pieceCount > 0 else { return }
            let available = min(pieceCount, data.count * 8)
            guard available > 0 else { return }

            let columns = max(1, min(available, Int(size.width)))
            let columnWidth = size.width / CGFloat(columns)
            for column in 0..<columns {
                let start = column * available / columns
                let end = min(available, max(start + 1, (column + 1) * available / columns))
                guard setBitCount(data, from: start, to: end) * 2 >= end - start else { continue }
                let rect = CGRect(
                    x: CGFloat(column) * columnWidth,
                    y: 0,
                    width: columnWidth + 0.5,
                    height: size.height
                )
                context.fill(Path(rect), with: .color(.blue))
            }
        }
    }

    /// Number of set bits in `data[start..<end]` (bit 7 of byte 0 is piece 0).
    private func setBitCount(_ data: Data, from start: Int, to end: Int) -> Int {
        var count = 0
        for index in start..<end {
            let byte = data[index / 8]
            if (byte >> UInt8(7 - (index % 8))) & 1 == 1 {
                count += 1
            }
        }
        return count
    }
}
