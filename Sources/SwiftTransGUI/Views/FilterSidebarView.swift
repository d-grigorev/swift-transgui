import SwiftUI
import TransGUICore

/// Left pane: status filters with counts, then folder/label/tracker groups.
struct FilterSidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.filter) {
            Section {
                ForEach(FilterID.allCases) { id in
                    row(
                        selection: .status(id),
                        title: id.title,
                        count: model.counts[id],
                        systemImage: id.systemImage,
                        tint: tint(for: id)
                    )
                }
            }

            if model.groupings.folders, !model.folderGroups.isEmpty {
                Section("Folders") {
                    ForEach(model.folderGroups) { group in
                        row(for: group)
                    }
                }
            }

            if !model.labelGroups.isEmpty {
                Section("Labels") {
                    ForEach(model.labelGroups) { group in
                        row(for: group)
                    }
                }
            }

            if !model.trackerGroups.isEmpty {
                Section("Trackers") {
                    ForEach(model.trackerGroups) { group in
                        row(for: group)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .listRowSeparator(.hidden)
        // Tight row insets keep labels + counts inside the narrow pane.
        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 8))
        .contextMenu {
            Toggle("Folder grouping", isOn: $model.groupings.folders)
            Toggle("Label grouping", isOn: $model.groupings.labels)
            Toggle("Tracker grouping", isOn: $model.groupings.trackers)
        }
        .disabled(!model.phase.isConnected && model.torrents.isEmpty)
    }

    private func row(for group: GroupOption) -> some View {
        row(
            selection: group.selection,
            title: group.title,
            count: group.count,
            systemImage: group.systemImage,
            tint: nil,
            detail: group.detail
        )
    }

    private func row(
        selection: FilterSelection,
        title: String,
        count: Int,
        systemImage: String,
        tint: Color?,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("(\(count))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .tag(selection)
        .help(detail ?? title)
    }

    private func tint(for id: FilterID) -> Color? {
        switch id {
        case .downloading: .blue
        case .completed: .green
        case .active: .orange
        case .error: .red
        default: nil
        }
    }
}
