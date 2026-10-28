import AppKit
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
                    .width(min: 70, ideal: 80, max: 110)
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
            // Uniform folder priority gets the same colored badge; mixed
            // folders stay blank like before.
            if let priority = row.priority {
                priorityBadge(priorityText(priority), priority: priority)
            }
        } else if let index = row.fileIndex {
            let priority = row.priority ?? 0
            Menu {
                Button("skip") { setPriority(-1000, index: index) }
                Button("low") { setPriority(-1, index: index) }
                Button("normal") { setPriority(0, index: index) }
                Button("high") { setPriority(1, index: index) }
            } label: {
                Text(priorityText(priority))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
            }
            .controlSize(.small)
            .menuStyle(.borderlessButton)
            .foregroundStyle(.primary)
            // One shared width for every row's dropdown (ruler: "normal").
            .frame(width: Self.priorityCellWidth)
            .background(
                priorityColor(priority).opacity(0.25),
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
    }

    /// Uniform priority-cell width: the word "normal" in the menu font plus
    /// badge padding and the menu chevron — every dropdown and folder badge
    /// in the column uses this one ruler, so all rows line up.
    static let priorityCellWidth: CGFloat = {
        let textWidth = ("normal" as NSString)
            .size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
        return ceil(textWidth) + 12 /* badge padding */ + 14 /* chevron + gap */
    }()

    static let priorityTextWidth: CGFloat = priorityCellWidth - 12

    /// Compact, value-colored priority badge:
    /// skip = gray, low = light blue, normal = light green, high = light red.
    /// Tints are opacity-based so they read as "light" colors in light mode
    /// and stay legible in dark mode.
    private func priorityBadge(_ text: String, priority: Int) -> some View {
        Text(text)
            .lineLimit(1)
            .frame(width: Self.priorityTextWidth, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(.primary)
            .background(
                priorityColor(priority).opacity(0.25),
                in: RoundedRectangle(cornerRadius: 4)
            )
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case ..<(-999): .gray  // skip (-1000)
        case ..<0: .blue  // low (-1)
        case 1...: .red  // high
        default: .green  // normal (0)
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
            // The checkmark mirrors the priority: skip → off, low/normal/high
            // → on.
            get: { row.priority != -1000 },
            set: { checked in
                guard let index = row.fileIndex,
                    let id = model.selection.sorted().first
                else { return }
                Task {
                    if checked {
                        // on → wanted with normal priority
                        await model.setFileWanted(
                            indices: [index], wanted: true, torrentId: id)
                    } else {
                        // off → skip (files-unwanted)
                        await model.setFilePriority(
                            indices: [index], priority: -1000, torrentId: id)
                    }
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
