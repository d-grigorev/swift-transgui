import SwiftUI
import TransGUICore

/// Which bottom-pane tab is showing.
enum DetailsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case trackers
    case peers
    case files
    case statistics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .trackers: "Trackers"
        case .peers: "Peers"
        case .files: "Files"
        case .statistics: "Statistics"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "info.circle"
        case .trackers: "antenna.radiowaves.left.and.right"
        case .peers: "person.2"
        case .files: "folder"
        case .statistics: "chart.bar"
        }
    }
}

/// Bottom pane: tabbed details for the selected torrent (General, Trackers,
/// Peers, Files, Statistics), mirroring the reference app's info pane.
struct DetailsPaneView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedDetailsTab) {
            GeneralDetailsView()
                .tabItem {
                    Label(DetailsTab.general.title, systemImage: DetailsTab.general.systemImage)
                }
                .tag(DetailsTab.general)

            TrackersDetailsView()
                .tabItem {
                    Label(DetailsTab.trackers.title, systemImage: DetailsTab.trackers.systemImage)
                }
                .tag(DetailsTab.trackers)

            PeersDetailsView()
                .tabItem {
                    Label(DetailsTab.peers.title, systemImage: DetailsTab.peers.systemImage)
                }
                .tag(DetailsTab.peers)

            FilesDetailsView()
                .tabItem {
                    Label(filesCaption, systemImage: DetailsTab.files.systemImage)
                }
                .tag(DetailsTab.files)

            StatisticsDetailsView()
                .tabItem {
                    Label(DetailsTab.statistics.title, systemImage: DetailsTab.statistics.systemImage)
                }
                .tag(DetailsTab.statistics)
        }
        .onChange(of: model.selection) { _, _ in
            model.selectionForDetailsChanged()
        }
        .onChange(of: model.selectedDetailsTab) { _, _ in
            model.detailsTabChanged()
        }
    }

    /// `Files (N)` once the file list is known (like the reference app).
    private var filesCaption: String {
        if let files = model.details?.files {
            return "Files (\(files.count))"
        }
        return DetailsTab.files.title
    }
}

// MARK: - Placeholder / loading state

/// Shown by a tab while no torrent is selected or its data has not arrived.
struct DetailsStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.selection.isEmpty {
                Text("Select a torrent to view details.")
            } else {
                ProgressView()
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Statistics tab

/// Statistics tab: global `session-stats` numbers, Current vs Cumulative.
struct StatisticsDetailsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.selection.isEmpty {
            DetailsStatusView()
        } else if let stats = model.stats,
            let current = stats.currentStats,
            let cumulative = stats.cumulativeStats
        {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Global statistics:")

                    Grid(alignment: .leading, horizontalSpacing: 36, verticalSpacing: 6) {
                        GridRow {
                            Text("")
                                .font(.headline)
                            Text("Current")
                                .font(.headline)
                            Text("Cumulative")
                                .font(.headline)
                        }
                        statRow(
                            "Downloaded",
                            Fmt.size(current.downloadedBytes),
                            Fmt.size(cumulative.downloadedBytes)
                        )
                        statRow(
                            "Uploaded",
                            Fmt.size(current.uploadedBytes),
                            Fmt.size(cumulative.uploadedBytes)
                        )
                        statRow(
                            "Files added",
                            countText(current.filesAdded),
                            countText(cumulative.filesAdded)
                        )
                        statRow(
                            "Active time",
                            Fmt.duration(current.secondsActive),
                            Fmt.duration(cumulative.secondsActive)
                        )
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
    }

    private func statRow(_ title: String, _ current: String, _ cumulative: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(current)
                .monospacedDigit()
            Text(cumulative)
                .monospacedDigit()
        }
    }

    private func countText(_ value: Int?) -> String {
        "\(value ?? 0)"
    }
}
