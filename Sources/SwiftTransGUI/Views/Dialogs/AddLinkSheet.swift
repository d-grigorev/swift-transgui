import SwiftUI
import TransGUICore

/// "Add torrent link" dialog: a single field for a .torrent URL or magnet
/// link. A bare 40-character infohash is converted to a magnet link.
struct AddLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var link = ""
    @State private var errorText: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("URL of a .torrent file or a magnet link:")

            TextField("", text: $link)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { submit() }

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
                Button("OK", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .navigationTitle("Add torrent link")
        .onAppear {
            focused = true
        }
    }

    private func submit() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorText = "No link was specified."
            return
        }
        // A bare infohash becomes a magnet link (reference behavior).
        let normalized =
            MagnetLink.isInfoHash(trimmed) ? MagnetLink.magnetFromInfoHash(trimmed) : trimmed
        dismiss()
        model.addTorrentLink(normalized)
    }
}
