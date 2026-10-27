import SwiftUI
import TransGUICore

struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        windowContent
            .toolbar {
                MainToolbar()
            }
            .sheet(isPresented: $model.showPasswordPrompt) {
                PasswordPromptView()
            }
            .sheet(item: $model.addTorrentSheet) { state in
                AddTorrentSheet(state: state)
            }
            .sheet(isPresented: $model.showAddLinkSheet) {
                AddLinkSheet()
            }
            .sheet(item: $model.propertiesSheet) { state in
                TorrentPropertiesSheet(state: state)
            }
            .sheet(item: $model.dataLocationSheet) { state in
                SetDataLocationSheet(state: state)
            }
            .sheet(item: $model.labelsSheet) { state in
                SetLabelsSheet(state: state)
            }
            .sheet(item: $model.renameSheet) { state in
                RenameSheet(state: state)
            }
            .sheet(isPresented: $model.showManageConnections) {
                ManageConnectionsSheet(
                    mode: model.manageConnectionsMode,
                    profiles: model.profiles,
                    currentId: model.currentProfileId
                )
            }
            .sheet(item: $model.transmissionOptionsSheet) { state in
                TransmissionOptionsSheet(state: state)
            }
            .sheet(isPresented: $model.showApplicationOptions) {
                ApplicationOptionsSheet()
            }
            .sheet(isPresented: $model.showColumnsSetup) {
                ColumnsSetupSheet(customization: model.torrentColumnCustomization)
            }
            .modifier(MainAlerts())
            .dropDestination(for: URL.self) { urls, _ in
                let torrentFiles = urls.filter {
                    $0.pathExtension.caseInsensitiveCompare("torrent") == .orderedSame
                        || (try? $0.resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier
                            == "public.torrent-file"
                }
                guard !torrentFiles.isEmpty else { return }
                model.addTorrentFiles(torrentFiles)
            }
            .animation(.default, value: model.phase)
    }

    /// The panes themselves (split out of `body` so the modifier chain
    /// above stays type-checkable).
    private var windowContent: some View {
        VStack(spacing: 0) {
            VSplitView {
                HSplitView {
                    if model.showFilterSidebar {
                        FilterSidebarView()
                            // The HSplit gave this pane its max width once the
                            // toolbar layout changed: cap both so it stays at
                            // "text with counts fits" width.
                            .frame(minWidth: 110, idealWidth: 165, maxWidth: 165)
                    }

                    TorrentTableView()
                        .frame(minWidth: 480)
                }
                .frame(maxHeight: .infinity)

                if model.showDetailsPane {
                    DetailsPaneView()
                        .frame(minHeight: 140, idealHeight: 260)
                }
            }
            .frame(maxHeight: .infinity)

            if model.showStatusBar {
                Divider()

                StatusBarView()
            }
        }
    }
}

// MARK: - Alerts

/// The window's confirmations and error alerts (remove, verify, duplicate,
/// shared errors, blocklist update). Kept in a separate modifier so the
/// main body expression stays small enough to type-check.
private struct MainAlerts: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .alert(
                "Update blocklist",
                isPresented: Binding(
                    get: { model.blocklistUpdateMessage != nil },
                    set: { if !$0 { model.blocklistUpdateMessage = nil } }
                ),
                presenting: model.blocklistUpdateMessage
            ) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
            .alert(
                "Remove torrent(s)",
                isPresented: Binding(
                    get: { model.removeConfirm != nil },
                    set: { if !$0 { model.removeConfirm = nil } }
                ),
                presenting: model.removeConfirm
            ) { confirm in
                // Clear synchronously (same reason as the duplicate alert)
                // and offer all three outcomes in one confirmation.
                Button("Remove") {
                    let ids = confirm.ids
                    model.removeConfirm = nil
                    Task { await model.remove(ids: ids, deleteData: false) }
                }
                Button("Remove and delete data") {
                    let ids = confirm.ids
                    model.removeConfirm = nil
                    Task { await model.remove(ids: ids, deleteData: true) }
                }
                Button("Cancel", role: .cancel) {
                    model.removeConfirm = nil
                }
            } message: { confirm in
                Text(confirm.message)
            }
            .alert(
                "Verify",
                isPresented: Binding(
                    get: { model.verifyConfirm != nil },
                    set: { if !$0 { model.verifyConfirm = nil } }
                ),
                presenting: model.verifyConfirm
            ) { confirm in
                Button("Verify") {
                    let ids = confirm.ids
                    model.verifyConfirm = nil
                    Task { await model.verify(ids: ids) }
                }
                Button("Cancel", role: .cancel) {
                    model.verifyConfirm = nil
                }
            } message: { _ in
                Text("Verify the selected torrent(s)?")
            }
            .alert(
                duplicateAlertTitle,
                isPresented: Binding(
                    get: { model.duplicateTorrentAlert != nil },
                    set: { if !$0 { model.dismissDuplicateAlert() } }
                ),
                presenting: model.duplicateTorrentAlert
            ) { alert in
                Button("Yes") {
                    // Clear synchronously so the dismiss binding (fired
                    // right after the action) does not treat this as an
                    // abandonment.
                    model.duplicateTorrentAlert = nil
                    Task { await model.resolveDuplicateAlert(alert, updateTrackers: true) }
                }
                Button("No") {
                    model.duplicateTorrentAlert = nil
                    Task { await model.resolveDuplicateAlert(alert, updateTrackers: false) }
                }
            } message: { _ in
                Text("Update trackers for the existing torrent?")
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { model.addTorrentError != nil },
                    set: { if !$0 { model.addTorrentError = nil } }
                ),
                presenting: model.addTorrentError
            ) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
    }

    /// Duplicate alert title mirrors the reference string, with the existing
    /// torrent's name appended when known.
    private var duplicateAlertTitle: String {
        guard let alert = model.duplicateTorrentAlert else {
            return "Torrent already exists in the list."
        }
        if let name = alert.name, !name.isEmpty {
            return "Torrent already exists in the list: \(name)."
        }
        return "Torrent already exists in the list."
    }
}

// MARK: - Status colors shared by rows and sidebar

extension DisplayStatus {
    var color: Color {
        switch self {
        case .downloading: .blue
        case .seeding: .green
        case .verifying: .blue
        case .waiting: .orange
        case .finished: .green
        case .stopped: .secondary
        case .unknown: .secondary
        }
    }
}
