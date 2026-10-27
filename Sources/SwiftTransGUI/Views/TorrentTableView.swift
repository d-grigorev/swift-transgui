import SwiftUI
import TransGUICore

/// The torrent table's customizable columns: the customization IDs, header
/// titles and default visibility. Shared by the table (`.customizationID`)
/// and the "Columns setup" dialog so the two cannot drift apart.
enum TorrentColumn: String, CaseIterable, Sendable {
    case name
    case size
    case done
    case status
    case seeds
    case peers
    case downSpeed
    case upSpeed
    case eta
    case ratio
    case queuePosition
    case labels

    var customizationId: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .size: "Size"
        case .done: "Done"
        case .status: "Status"
        case .seeds: "Seeds"
        case .peers: "Peers"
        case .downSpeed: "Down speed"
        case .upSpeed: "Up speed"
        case .eta: "ETA"
        case .ratio: "Ratio"
        case .queuePosition: "Queue position"
        case .labels: "Labels"
        }
    }

    /// Reference default: only the queue position starts hidden.
    var isHiddenByDefault: Bool {
        self == .queuePosition
    }
}

/// Center pane: the sortable torrent list.
struct TorrentTableView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder: [KeyPathComparator<Torrent>] = []

    var body: some View {
        @Bindable var model = model

        Table(
            model.sorted(model.visibleTorrents, by: sortOrder),
            selection: $model.selection,
            sortOrder: $sortOrder,
            columnCustomization: $model.torrentColumnCustomization
        ) {
            primaryColumns
            secondaryColumns
        }
        .onChange(of: model.torrentColumnCustomization) { _, _ in
            // Header drag-reorder / show-hide and the Columns setup dialog
            // both land here; persist for the next launch.
            model.saveColumnCustomization()
        }
        .overlay {
            emptyState
        }
        .contextMenu(
            forSelectionType: Int.self,
            menu: { clicked in
                contextMenuContent(actionIds(clicked))
            },
            primaryAction: { _ in
                // Reference behavior: the primary action (double-click)
                // opens the torrent properties dialog.
                Task { await model.presentProperties() }
            }
        )
    }

    /// The context menu acts on the clicked rows plus the current selection
    /// (like the reference app, where a right-click acts on all selected).
    @MainActor
    private func actionIds(_ clicked: Set<Int>) -> [Int] {
        Array(clicked.union(model.selection)).sorted()
    }

    @ViewBuilder
    @MainActor
    private func contextMenuContent(_ ids: [Int]) -> some View {
        let empty = ids.isEmpty

        Button("Start") {
            Task { await model.start(ids: ids) }
        }
        .disabled(empty)

        Button("Force start") {
            Task { await model.forceStart(ids: ids) }
        }
        .disabled(empty || model.rpcVersion < 14)

        Button("Stop") {
            Task { await model.stop(ids: ids) }
        }
        .disabled(empty)

        Button("Remove") {
            model.askRemove(ids: ids)
        }
        .disabled(empty)

        Button("Remove torrent and Data") {
            model.askRemove(ids: ids, asksData: true)
        }
        .disabled(empty || model.rpcVersion < 4)

        Divider()

        Menu("Priority") {
            Button("High") {
                Task { await model.setBandwidthPriority(ids: ids, priority: 1) }
            }
            Button("Normal") {
                Task { await model.setBandwidthPriority(ids: ids, priority: 0) }
            }
            Button("Low") {
                Task { await model.setBandwidthPriority(ids: ids, priority: -1) }
            }
        }
        .disabled(empty)

        Menu("Queue") {
            Button("Move top") {
                Task { await model.queueMove(ids: ids, position: .top) }
            }
            Button("Move up") {
                Task { await model.queueMove(ids: ids, position: .up) }
            }
            Button("Move down") {
                Task { await model.queueMove(ids: ids, position: .down) }
            }
            Button("Move bottom") {
                Task { await model.queueMove(ids: ids, position: .bottom) }
            }
        }
        .disabled(empty)

        Button("Reannounce (get more peers)") {
            Task { await model.reannounce(ids: ids) }
        }
        .disabled(empty)

        Button("Verify") {
            model.askVerify(ids: ids)
        }
        .disabled(empty)

        Button("Copy Magnet Link(s)") {
            Task { await model.copyMagnetLinks(ids: ids) }
        }
        .disabled(empty)

        Button("Set data location...") {
            model.presentDataLocation(ids: ids)
        }
        .disabled(empty || model.rpcVersion < 6)

        Button("Set labels...") {
            model.presentLabels(ids: ids)
        }
        .disabled(empty || model.rpcVersion < 16)

        Button("Rename") {
            model.presentRename(id: ids.first)
        }
        .disabled(empty || model.rpcVersion < 15)

        Divider()

        Button("Properties...") {
            Task { await model.presentProperties(ids: ids) }
        }
        .disabled(empty)
    }

    // TableColumnBuilder supports up to 10 columns per group, so the list is
    // split into two groups (12 columns total). Every column carries its
    // customization ID and default visibility for the header's native
    // show/hide + drag-reorder menu and the "Columns setup" dialog.
    @TableColumnBuilder<Torrent, KeyPathComparator<Torrent>>
    private var primaryColumns: some TableColumnContent<Torrent, KeyPathComparator<Torrent>> {
        TableColumn(TorrentColumn.name.title, value: \Torrent.nameSortKey) { torrent in
            NameCell(torrent: torrent)
        }
        .width(min: 180, ideal: 320, max: 900)
        .customizationID(TorrentColumn.name.customizationId)
        .defaultVisibility(.visible)

        TableColumn(TorrentColumn.size.title, value: \Torrent.totalSizeSort) { torrent in
            cellText(sizeText(torrent), align: .trailing)
        }
        .width(min: 60, ideal: 80)
        .customizationID(TorrentColumn.size.customizationId)
        .defaultVisibility(.visible)

        TableColumn(TorrentColumn.done.title, value: \Torrent.progressFraction) { torrent in
            ProgressCell(fraction: torrent.progressFraction, text: torrent.progressText)
        }
        .width(min: 70, ideal: 90, max: 160)
        .customizationID(TorrentColumn.done.customizationId)
        .defaultVisibility(.visible)

        TableColumn(TorrentColumn.status.title, value: \Torrent.statusRaw) { torrent in
            Text(torrent.displayStatus.rawValue)
                .foregroundStyle(torrent.hasError ? Color.red : .primary)
                .help(torrent.effectiveError ?? torrent.displayStatus.rawValue)
        }
        .width(min: 70, ideal: 85)
        .customizationID(TorrentColumn.status.customizationId)
        .defaultVisibility(.visible)

        TableColumn(TorrentColumn.seeds.title, value: \Torrent.seedsSort) { torrent in
            cellText(torrent.seedsText, align: .trailing)
        }
        .width(min: 50, ideal: 60)
        .customizationID(TorrentColumn.seeds.customizationId)
        .defaultVisibility(.visible)

        TableColumn(TorrentColumn.peers.title, value: \Torrent.peersSort) { torrent in
            cellText(torrent.peersText, align: .trailing)
        }
        .width(min: 50, ideal: 60)
        .customizationID(TorrentColumn.peers.customizationId)
        .defaultVisibility(.visible)

        TableColumn(TorrentColumn.downSpeed.title, value: \Torrent.downSpeed) { torrent in
            cellText(Fmt.speed(torrent.downSpeed), align: .trailing)
        }
        .width(min: 70, ideal: 85)
        .customizationID(TorrentColumn.downSpeed.customizationId)
        .defaultVisibility(.visible)

        TableColumn(TorrentColumn.upSpeed.title, value: \Torrent.upSpeed) { torrent in
            cellText(Fmt.speed(torrent.upSpeed), align: .trailing)
        }
        .width(min: 70, ideal: 85)
        .customizationID(TorrentColumn.upSpeed.customizationId)
        .defaultVisibility(.visible)

        TableColumn(TorrentColumn.eta.title, value: \Torrent.etaForSort) { torrent in
            cellText(Fmt.eta(torrent.etaForSort), align: .trailing)
        }
        .width(min: 60, ideal: 80)
        .customizationID(TorrentColumn.eta.customizationId)
        .defaultVisibility(.visible)

        TableColumn(TorrentColumn.ratio.title, value: \Torrent.ratioForSort) { torrent in
            cellText(Fmt.ratio(torrent.uploadRatio), align: .trailing)
        }
        .width(min: 55, ideal: 65)
        .customizationID(TorrentColumn.ratio.customizationId)
        .defaultVisibility(.visible)
    }

    @TableColumnBuilder<Torrent, KeyPathComparator<Torrent>>
    private var secondaryColumns: some TableColumnContent<Torrent, KeyPathComparator<Torrent>> {
        TableColumn(TorrentColumn.queuePosition.title, value: \Torrent.queueSort) { torrent in
            cellText("\(torrent.queueSort)", align: .trailing)
        }
        .width(min: 50, ideal: 60, max: 80)
        .customizationID(TorrentColumn.queuePosition.customizationId)
        .defaultVisibility(.hidden)

        TableColumn(TorrentColumn.labels.title, value: \Torrent.labelsText) { torrent in
            let labels = torrent.labelsText
            cellText(labels.isEmpty ? nil : labels)
        }
        .width(min: 70, ideal: 120, max: 300)
        .customizationID(TorrentColumn.labels.customizationId)
        .defaultVisibility(.visible)
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.phase == .connecting || (model.phase.isConnected && model.torrents.isEmpty) {
            ProgressView(model.phase.isConnected ? "Loading torrents..." : "Connecting...")
                .controlSize(.large)
                .padding(40)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if !model.phase.isConnected {
            ContentUnavailableView {
                Label("Not connected", systemImage: "plug")
            } description: {
                Text(model.statusCaption)
            } actions: {
                Button("Connect to Transmission") {
                    Task { await model.connect() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func sizeText(_ torrent: Torrent) -> String? {
        let size = torrent.totalSizeSort
        return size < 0 ? nil : Fmt.size(size)
    }

    private func cellText(_ text: String?, align: HorizontalAlignment = .leading) -> some View {
        HStack {
            if align == .trailing { Spacer(minLength: 0) }
            Text(text ?? "")
                .monospacedDigit()
                .foregroundStyle(text == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if align == .leading { Spacer(minLength: 0) }
        }
    }
}

// MARK: - Name cell (status icon + name)

struct NameCell: View {
    let torrent: Torrent

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: torrent.displayStatus.systemImage)
                .foregroundStyle(torrent.displayStatus.color)
                .frame(width: 16)
            Text(torrent.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(torrent.displayName)
    }
}

// MARK: - Progress bar cell (the "Done" column)

struct ProgressCell: View {
    let fraction: Double
    let text: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    }

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.85), .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth(total: geo.size.width))

                Text(text)
                    .font(.system(size: 10).monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(fraction > 0.55 ? Color.white : Color.primary)
            }
        }
        .frame(height: 14)
        .padding(.vertical, 1)
    }

    private func barWidth(total: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        let w = total * fraction
        return max(3, min(w, total))
    }
}

// MARK: - Sort support

private extension Torrent {
    /// Sort key for the Status column.
    var statusRaw: String {
        displayStatus.rawValue
    }

    /// Empty string instead of `nil` (table sort keys must be non-optional).
    var nameSortKey: String {
        displayName
    }

    /// `-1` when the size is unknown (metadata not yet fetched).
    var totalSizeSort: Int64 {
        if let size = totalSize, size >= 0 { return size }
        if let size = sizeWhenDone, size >= 0 { return size }
        return -1
    }

    var queueSort: Int {
        queuePosition ?? 0
    }
}
