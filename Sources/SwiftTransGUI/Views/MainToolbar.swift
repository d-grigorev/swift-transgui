import SwiftUI
import TransGUICore

/// Window toolbar: connection menu, add/start/stop/remove, queue moves,
/// the alternate-speed toggle and the search box.
struct MainToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        // The window title ("SwiftTransGUI") leads the toolbar; the
        // connection menu sits at the head of the action group, so the
        // name and the Connect button read left-to-right in that order.
        ToolbarItemGroup(placement: .automatic) {
            connectMenu

            if model.phase == .connecting {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.pickTorrentFiles()
            } label: {
                Label("Add torrent...", systemImage: "plus")
            }
            .help("Add torrent")
            .disabled(!model.phase.isConnected)

            Divider()

            Button {
                Task { await model.start() }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .help("Start torrent (F3)")
            .disabled(!model.canAct)

            Button {
                Task { await model.stop() }
            } label: {
                Label("Stop", systemImage: "pause.fill")
            }
            .help("Stop torrent (F4)")
            .disabled(!model.canAct)

            Button {
                model.askRemove()
            } label: {
                Label("Remove", systemImage: "trash.fill")
            }
            .help("Remove torrent (Delete)")
            .disabled(!model.canAct)

            Divider()

            Button {
                Task { await model.queueMove(position: .up) }
            } label: {
                Label("Move up queue", systemImage: "arrow.up.circle")
            }
            .help("Move up queue (Ctrl+1)")
            .disabled(!model.canAct)

            Button {
                Task { await model.queueMove(position: .down) }
            } label: {
                Label("Move down queue", systemImage: "arrow.down.circle")
            }
            .help("Move down queue (Ctrl+2)")
            .disabled(!model.canAct)

            Divider()

            altSpeedToggle

            SearchField()
        }
    }

    /// Connection menu: the profiles with a checkmark on the current one,
    /// then the dialog entry points. The label is the connected profile's
    /// name, or "Connect to Transmission" while disconnected (the
    /// reference app's connect button behaves the same way).
    private var connectMenu: some View {
        Menu {
            ForEach(model.profiles) { profile in
                Toggle(profile.displayName, isOn: Binding(
                    get: { profile.id == model.currentProfileId },
                    set: { _ in
                        Task { await model.connect(to: profile) }
                    }
                ))
            }

            Divider()

            Button("New connection...") {
                model.presentManageConnections(mode: .new)
            }
            Button("Manage connections...") {
                model.presentManageConnections(mode: .manage)
            }
        } label: {
            Label(connectCaption, systemImage: model.phase.isConnected ? "plug.fill" : "power")
        }
        .help("Connect to Transmission")
    }

    private var connectCaption: String {
        guard model.phase.isConnected else { return "Connect to Transmission" }
        return model.profiles.first { $0.id == model.currentProfileId }?.displayName
            ?? model.endpoint.name
    }

    /// Turtle-mode toggle bound to `session.alt-speed-enabled`: the state
    /// comes from the daemon, clicks send `session-set` and refresh.
    private var altSpeedToggle: some View {
        Toggle(isOn: Binding(
            get: { model.session?.altSpeedEnabled ?? false },
            set: { newValue in
                if newValue != (model.session?.altSpeedEnabled ?? false) {
                    Task { await model.toggleAltSpeedEnabled() }
                }
            }
        )) {
            Label("Use alternate bandwidth settings", systemImage: "tortoise.fill")
        }
        .toggleStyle(.button)
        .help("Use alternate bandwidth settings (F8)")
        .keyboardShortcut(Key.f8, modifiers: [])
        .disabled(model.session == nil)
    }
}

private struct SearchField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $model.searchText)
                .textFieldStyle(.plain)
                .frame(minWidth: 60, maxWidth: 180)
                .focused($focused)
                .onExitCommand {
                    model.searchText = ""
                }

            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search (Esc)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .help("Filter torrents by keywords")
        .onChange(of: model.focusSearchTick) { _, _ in
            // View > Search (Alt+S): take focus for typing.
            focused = true
        }
    }
}
