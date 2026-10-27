import SwiftUI
import TransGUICore

// MARK: - Files tab

/// Files tab: a folder tree (File name / Size / Done / % / Priority) with
/// wanted checkboxes and a priority menu that issue `torrent-set` calls.
struct FilesDetailsView: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []
    @State private var sortOrder: [KeyPathComparator<FileTreeRow>] = []

    var body: some View {
        if model.details?.files != nil {
            let rows = visibleRows()
            if rows.isEmpty {
                Text("No files.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("File name", value: \FileTreeRow.name) { row in
                        nameCell(row)
                    }
                    .width(min: 240, ideal: 420)

                    TableColumn("Size", value: \FileTreeRow.size) { row in
                        cellText(Fmt.size(row.size), align: .trailing)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Done", value: \FileTreeRow.done) { row in
                        cellText(Fmt.size(row.done), align: .trailing)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("%", value: \FileTreeRow.percentSort) { row in
                        cellText(percentText(row), align: .trailing)
                    }
                    .width(min: 50, ideal: 60)

                    TableColumn("Priority", value: \FileTreeRow.prioritySort) { row in
                        priorityCell(row)
                    }
                    .width(min: 70, ideal: 90)
                }
                // Tighter vertical rhythm: no extra automatic row padding and
                // small controls (checkbox / priority popup).
                .contentMargins(.vertical, 0, for: .automatic)
            }
        } else {
            DetailsStatusView()
        }
    }

    // MARK: Cells

    @ViewBuilder
    private func nameCell(_ row: FileTreeRow) -> some View {
        HStack(spacing: 4) {
            if row.depth > 0 {
                Color.clear
                    .frame(width: CGFloat(row.depth) * 14, height: 1)
            }
            if row.isFolder {
                Button {
                    toggle(row.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed.contains(row.id) ? 0 : 90))
                }
                .buttonStyle(.plain)
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.id)
            } else {
                Toggle("", isOn: wantedBinding(row))
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .labelsHidden()
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.id)
            }
        }
    }

    @ViewBuilder
    private func priorityCell(_ row: FileTreeRow) -> some View {
        if row.isFolder {
            Text(row.priority.map(priorityText) ?? "")
                .foregroundStyle(.secondary)
        } else if let index = row.fileIndex {
            Menu {
                Button("skip") { setPriority(-1000, index: index) }
                Button("low") { setPriority(-1, index: index) }
                Button("normal") { setPriority(0, index: index) }
                Button("high") { setPriority(1, index: index) }
            } label: {
                Text(priorityText(row.priority ?? 0))
            }
            .controlSize(.small)
        }
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

    private func percentText(_ row: FileTreeRow) -> String {
        guard row.size > 0 else { return "-" }
        return Fmt.percent(Double(row.done) / Double(row.size))
    }

    private func priorityText(_ priority: Int) -> String {
        if priority <= -1000 { return "skip" }
        if priority < 0 { return "low" }
        if priority > 0 { return "high" }
        return "normal"
    }

    // MARK: Actions

    private func toggle(_ path: String) {
        if collapsed.contains(path) {
            collapsed.remove(path)
        } else {
            collapsed.insert(path)
        }
    }

    private func wantedBinding(_ row: FileTreeRow) -> Binding<Bool> {
        Binding(
            get: { row.wanted },
            set: { newValue in
                guard let index = row.fileIndex,
                    let id = model.selection.sorted().first
                else { return }
                Task {
                    await model.setFileWanted(indices: [index], wanted: newValue, torrentId: id)
                }
            }
        )
    }

    private func setPriority(_ priority: Int, index: Int) {
        guard let id = model.selection.sorted().first else { return }
        Task {
            await model.setFilePriority(indices: [index], priority: priority, torrentId: id)
        }
    }

    // MARK: Tree building

    private func visibleRows() -> [FileTreeRow] {
        FileTree.rows(
            files: model.details?.files ?? [],
            priorities: model.details?.priorities ?? [],
            wanted: model.details?.wanted ?? [],
            collapsed: collapsed,
            sortBy: sortOrder
        )
    }
}
