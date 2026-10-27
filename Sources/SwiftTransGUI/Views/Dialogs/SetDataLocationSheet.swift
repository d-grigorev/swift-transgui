import AppKit
import SwiftUI
import TransGUICore

/// "Torrent data location" dialog: a new location for the selected
/// torrents' data with the destination history, plus the option to move
/// the data there (mirroring the reference app's move form).
struct SetDataLocationSheet: View {
    let state: DataLocationSheetState

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var path: String
    @State private var moveData = true
    @State private var errorText: String?
    @FocusState private var focused: Bool

    init(state: DataLocationSheetState) {
        self.state = state
        _path = State(initialValue: state.currentPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New location for torrent data:")

            HStack(spacing: 4) {
                TextField("", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(submit)
                destinationHistoryMenu
                Button("Browse...") {
                    browse()
                }
            }

            Toggle("Move torrent data from current location to new location", isOn: $moveData)
                .toggleStyle(.checkbox)

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
        .frame(width: 560)
        .navigationTitle("Torrent data location")
        .onAppear {
            focused = true
        }
    }

    /// Destination history plus the session download dir (same source the
    /// add-torrent dialog offers).
    private var destinationHistory: [String] {
        var folders = AddTorrentDefaults.destinations
        if let dir = model.session?.downloadDir, !dir.isEmpty, !folders.contains(dir) {
            folders.insert(dir, at: 0)
        }
        if !state.currentPath.isEmpty, !folders.contains(state.currentPath) {
            folders.insert(state.currentPath, at: 0)
        }
        return folders
    }

    private var destinationHistoryMenu: some View {
        Menu {
            if destinationHistory.isEmpty {
                Text("No history")
            } else {
                ForEach(destinationHistory, id: \.self) { folder in
                    Button(folder) {
                        path = folder
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
        .help("Recent destination folders")
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }

    private func submit() {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorText = "No torrent location was specified."
            return
        }
        dismiss()
        let move = moveData
        Task { await model.applyDataLocation(state, path: trimmed, move: move) }
    }
}
