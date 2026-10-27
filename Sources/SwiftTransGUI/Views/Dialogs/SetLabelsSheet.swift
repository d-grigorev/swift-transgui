import SwiftUI
import TransGUICore

/// "Set labels" dialog: replaces the labels of every selected torrent with
/// the comma-separated list entered here (an empty field clears them,
/// like the reference app's input box).
struct SetLabelsSheet: View {
    let state: LabelsSheetState

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @FocusState private var focused: Bool

    init(state: LabelsSheetState) {
        self.state = state
        _text = State(initialValue: state.initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                GridRow {
                    Text("Labels:")
                    TextField("", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(submit)
                }
            }
            .gridColumnAlignment(.trailing)

            Text("This will overwrite any existing labels. You can set multiple labels separated by a comma or leave empty to clear labels.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        .frame(width: 460)
        .navigationTitle("Set labels")
        .onAppear {
            focused = true
        }
    }

    private func submit() {
        let labels = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        dismiss()
        Task { await model.applyLabels(state, labels: labels) }
    }
}
