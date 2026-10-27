import SwiftUI
import TransGUICore

/// Password prompt shown on first connection (and after a rejected password).
/// The password is stored in the Keychain after a successful connection.
struct PasswordPromptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect to \(model.endpoint.name)")
                    .font(.headline)
                Text(
                    "Please enter a password to connect to "
                        + "\(model.endpoint.host):\(model.endpoint.port):"
                )
                .foregroundStyle(.secondary)
            }

            SecureField("", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { submit() }

            if let error = model.passwordError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancelPasswordPrompt()
                    dismiss()
                }
                Button("Connect", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            focused = true
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        let value = password
        password = ""
        dismiss()
        Task {
            await model.submitPassword(value)
        }
    }
}
