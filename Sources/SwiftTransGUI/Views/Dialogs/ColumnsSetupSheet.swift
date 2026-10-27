import SwiftUI
import TransGUICore

/// "Columns setup - Torrents": a checklist of the torrent table's columns
/// (checked = visible). At least one column must stay visible; the column
/// *order* is changed by dragging the table headers (or the header's
/// context menu) because `TableColumnCustomization` exposes no ordering
/// API — so the reference's Up/Down buttons are omitted here.
struct ColumnsSetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Checked state per `TorrentColumn` (same order as the table).
    @State private var checked: [Bool]
    @State private var errorText: String?

    init(customization: TableColumnCustomization<Torrent>) {
        _checked = State(
            initialValue: TorrentColumn.allCases.map { column in
                let state = customization[visibility: column.customizationId]
                switch state {
                case .hidden:
                    return false
                case .visible:
                    return true
                default:
                    return !column.isHiddenByDefault
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(TorrentColumn.allCases.enumerated()), id: \.element) {
                    index,
                    column in
                    Toggle(column.title, isOn: binding(for: index))
                        .toggleStyle(.checkbox)
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("OK", action: ok)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .navigationTitle("Columns setup - Torrents")
    }

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { checked[index] },
            set: { checked[index] = $0 }
        )
    }

    private func ok() {
        guard checked.contains(true) else {
            errorText = "At least single column must be visible."
            return
        }
        var customization = model.torrentColumnCustomization
        for (index, column) in TorrentColumn.allCases.enumerated() {
            customization[visibility: column.customizationId] =
                checked[index] ? .visible : .hidden
        }
        model.torrentColumnCustomization = customization
        dismiss()
    }
}
