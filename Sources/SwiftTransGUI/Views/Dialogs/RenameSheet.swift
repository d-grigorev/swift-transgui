import SwiftUI
import TransGUICore

/// "Rename" dialog: one input for the torrent's new name. Names containing
/// the invalid characters `* ? | < > " ~` (or an empty name) are rejected,
/// like the reference app's rename validation.
struct RenameSheet: View {
    let state: RenameSheetState

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var errorText: String?
    @FocusState private var focused: Bool

    init(state: RenameSheetState) {
        self.state = state
        _name = State(initialValue: state.currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New name:")

            TextField("", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)

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
        .frame(width: 420)
        .navigationTitle("Rename")
        .onAppear {
            focused = true
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(trimmed) else {
            errorText = "Invalid name specified."
            return
        }
        dismiss()
        Task { await model.applyRename(state, newName: trimmed) }
    }

    /// Non-empty and free of the characters the daemon/OS reject.
    private func isValid(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return !name.contains(where: { "*?|<>\"~".contains($0) })
    }
}
