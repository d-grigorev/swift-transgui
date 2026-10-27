import SwiftUI
import TransGUICore

/// "Manage connections to Transmission" / "New connection to Transmission":
/// pick, create, rename or delete connection profiles and edit how the
/// current one connects (the reference app's connoptions dialog).
///
/// The working copy lives in this sheet; OK hands the whole list to
/// `AppModel.updateProfiles`, Cancel throws the edits away. The built-in
/// default profile can be renamed but never deleted.
struct ManageConnectionsSheet: View {
    let mode: ManageConnectionsMode

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Working copy of the profiles (includes a blank one in new-mode).
    @State private var profiles: [ConnectionProfile]
    @State private var selectedId: String
    /// The combo box is replaced by a name field while renaming.
    @State private var renaming = false
    @State private var nameField = ""
    /// "Authentication required" is derived from the credentials but kept
    /// as its own switch so it can be turned on before a name is typed.
    @State private var authEnabled = false
    @State private var passwordField = ""
    /// The profile already has a Keychain password (shown as bullets).
    @State private var hasStoredPassword = false
    @State private var errorText: String?
    /// Id of the profile whose deletion is being confirmed (nil = no alert).
    @State private var confirmDeleteId: String?

    @FocusState private var nameFocused: Bool

    init(
        mode: ManageConnectionsMode,
        profiles: [ConnectionProfile],
        currentId: String
    ) {
        self.mode = mode
        var list = profiles
        var selected = currentId
        if mode == .new {
            let fresh = ConnectionProfile.blank()
            list.append(fresh)
            selected = fresh.id
        }
        _profiles = State(initialValue: list)
        _selectedId = State(initialValue: selected)
        _renaming = State(initialValue: mode == .new)
        _nameField = State(initialValue: mode == .new ? "" : (list.first { $0.id == selected }?.name ?? ""))
    }

    private var selected: ConnectionProfile? {
        profiles.first { $0.id == selectedId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topRow

            TabView {
                transmissionTab
                    .tabItem { Text("Transmission") }
            }
            .frame(minHeight: 230)

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
        .frame(width: 560)
        .navigationTitle(
            mode == .new ? "New connection to Transmission" : "Manage connections to Transmission"
        )
        .onAppear {
            refreshCredentialState()
            if renaming {
                nameFocused = true
            }
        }
        .alert(
            deleteConfirmTitle,
            isPresented: Binding(
                get: { confirmDeleteId != nil },
                set: { if !$0 { confirmDeleteId = nil } }
            ),
            presenting: confirmDeleteId
        ) { id in
            Button("Yes") {
                confirmDeleteId = nil
                deleteProfile(id: id)
            }
            Button("No", role: .cancel) {
                confirmDeleteId = nil
            }
        }
    }

    private var deleteConfirmTitle: String {
        let name = profiles.first { $0.id == confirmDeleteId }?.displayName ?? ""
        return "Are you sure to delete connection '\(name)'?"
    }

    // MARK: Top row (name combo + New / Rename / Delete)

    private var topRow: some View {
        HStack(spacing: 8) {
            Text("Connection name:")

            if renaming || selected?.name.trimmingCharacters(in: .whitespaces).isEmpty == true {
                TextField("", text: $nameField)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
                    .focused($nameFocused)
                    .onSubmit { commitRename() }
            } else {
                Picker("", selection: $selectedId) {
                    ForEach(profiles) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 200)
                .onChange(of: selectedId) { oldId, _ in
                    if renaming {
                        commitRename(profileId: oldId)
                    }
                    refreshCredentialState()
                }
            }

            Spacer(minLength: 8)

            Button("New", action: newProfile)
            Button("Rename", action: toggleRename)
            Button("Delete") {
                confirmDeleteId = selectedId
            }
            .disabled(selected?.isDefault == true)
        }
    }

    // MARK: Transmission tab

    private var transmissionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "Please specify how SwiftTransGUI will connect to a remote host "
                        + "running Transmission daemon (service)."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("Remote host:")
                        TextField("", text: field(\.host))
                            .frame(maxWidth: .infinity)
                    }

                    GridRow {
                        Text("Port:")
                        HStack(spacing: 14) {
                            TextField("", value: field(\.port), format: .number)
                                .frame(width: 90)
                            Toggle("Use SSL", isOn: field(\.useSSL))
                        }
                    }

                    GridRow {
                        Toggle("Authentication required", isOn: $authEnabled)
                        Toggle("Always auto-reconnect", isOn: field(\.alwaysReconnect))
                    }

                    GridRow {
                        Text("User name:")
                            .padding(.leading, 16)
                        TextField("", text: field(\.username))
                            .disabled(!authEnabled)
                    }

                    GridRow {
                        Text("Password:")
                            .padding(.leading, 16)
                        passwordFieldView
                    }

                    GridRow {
                        Text("RPC path:")
                        TextField("", text: field(\.rpcPath))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var passwordFieldView: some View {
        SecureField(
            hasStoredPassword && passwordField.isEmpty ? "••••••••" : "",
            text: $passwordField
        )
        .disabled(!authEnabled)
    }

    // MARK: Actions

    private func newProfile() {
        if renaming {
            commitRename()
        }
        let fresh = ConnectionProfile.blank()
        profiles.append(fresh)
        selectedId = fresh.id
        renaming = true
        nameField = ""
        passwordField = ""
        hasStoredPassword = false
        authEnabled = false
        errorText = nil
        nameFocused = true
    }

    private func toggleRename() {
        if renaming {
            commitRename()
        } else {
            renaming = true
            nameField = selected?.name ?? ""
            nameFocused = true
        }
    }

    /// Store the typed name (empty falls back to the host, duplicates get
    /// a " (2)" suffix — the reference app's EndEdit rules).
    private func commitRename(profileId: String? = nil) {
        guard renaming else { return }
        let id = profileId ?? selectedId
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            renaming = false
            return
        }
        var name = nameField.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            name = profiles[index].host.trimmingCharacters(in: .whitespaces)
        }
        if !name.isEmpty {
            var candidate = name
            var suffix = 2
            while profiles.contains(where: { $0.id != id && $0.name == candidate }) {
                candidate = "\(name) (\(suffix))"
                suffix += 1
            }
            profiles[index].name = candidate
        }
        renaming = false
    }

    private func deleteProfile(id: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        guard !profiles[index].isDefault else { return }
        profiles.remove(at: index)
        if selectedId == id {
            let next = profiles.first { $0.isDefault }
                ?? profiles[min(index, profiles.count - 1)]
            selectedId = next.id
        }
        renaming = false
        refreshCredentialState()
    }

    /// Re-sync the credential controls with the newly selected profile.
    private func refreshCredentialState() {
        guard let profile = selected else { return }
        hasStoredPassword = Keychain.load(account: profile.endpoint.keychainAccount) != nil
        authEnabled = !profile.username.isEmpty || hasStoredPassword
        passwordField = ""
        if !renaming {
            nameField = profile.name
        }
        errorText = nil
    }

    private func ok() {
        if renaming {
            commitRename()
        }

        // Every profile must have a host (the reference validates the
        // visible one; we validate the whole list before saving).
        if let broken = profiles.first(where: {
            $0.host.trimmingCharacters(in: .whitespaces).isEmpty
        }) {
            selectedId = broken.id
            refreshCredentialState()
            errorText = "No host name specified."
            return
        }

        for index in profiles.indices {
            profiles[index].host = profiles[index].host.trimmingCharacters(in: .whitespaces)
            profiles[index].port = min(65535, max(1, profiles[index].port))
            profiles[index].rpcPath = profiles[index].rpcPath.trimmingCharacters(in: .whitespaces)
            if profiles[index].id == selectedId {
                if authEnabled {
                    profiles[index].username =
                        profiles[index].username.trimmingCharacters(in: .whitespaces)
                } else {
                    // Turning authentication off drops the credentials, like
                    // the reference app's save logic (both the edited and
                    // the previously stored account are cleared).
                    profiles[index].username = ""
                    Keychain.delete(account: profiles[index].endpoint.keychainAccount)
                    if let original = model.profiles.first(where: { $0.id == selectedId }) {
                        Keychain.delete(account: original.endpoint.keychainAccount)
                    }
                }
            }
        }
        normalizeNames()

        if authEnabled, !passwordField.isEmpty,
            let index = profiles.firstIndex(where: { $0.id == selectedId })
        {
            // Only a freshly typed password overwrites the Keychain entry.
            Keychain.save(passwordField, account: profiles[index].endpoint.keychainAccount)
        }

        let saved = profiles
        dismiss()
        Task { await model.updateProfiles(saved) }
    }

    /// Blank names fall back to the host; duplicates get a suffix.
    private func normalizeNames() {
        var used = Set<String>()
        for index in profiles.indices {
            var name = profiles[index].name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                name = profiles[index].host
            }
            var candidate = name
            var suffix = 2
            while used.contains(candidate) {
                candidate = "\(name) (\(suffix))"
                suffix += 1
            }
            used.insert(candidate)
            profiles[index].name = candidate
        }
    }

    // MARK: Bindings

    /// Live binding into the selected profile's working copy. The value
    /// captured at render time is only a fallback for the moment between
    /// a profile disappearing and the next render (the selection always
    /// points at an existing profile).
    private func field<T>(_ keyPath: WritableKeyPath<ConnectionProfile, T>) -> Binding<T> {
        let fallback = selected?[keyPath: keyPath]
        return Binding(
            get: { selected?[keyPath: keyPath] ?? fallback! },
            set: { newValue in
                if let index = profiles.firstIndex(where: { $0.id == selectedId }) {
                    profiles[index][keyPath: keyPath] = newValue
                }
            }
        )
    }
}
