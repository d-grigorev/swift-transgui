import SwiftUI
import TransGUICore

/// "Application options": the client-side settings (the reference app's
/// options dialog, minus the Windows-only/tray/RTL pages). General covers
/// polling and the add-torrent flow; Misc holds the speed-limit menu
/// presets used by the status-bar context menus.
struct ApplicationOptionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // General
    @State private var refreshInterval = AppSettings.refreshInterval
    @State private var refreshIntervalMinimized = AppSettings.refreshIntervalMinimized
    @State private var averageSpeeds = AppSettings.averageSpeeds
    @State private var promptDownloadOptions = AppSettings.promptDownloadOptions
    @State private var deleteTorrentFile = AppSettings.deleteTorrentFile
    @State private var linksFromClipboard = AppSettings.linksFromClipboard

    // Misc
    @State private var speedMenuDown = AppSettings.speedMenuDown
    @State private var speedMenuUp = AppSettings.speedMenuUp

    var body: some View {
        VStack(spacing: 12) {
            TabView {
                generalTab
                    .tabItem { Text("General") }
                miscTab
                    .tabItem { Text("Misc") }
            }
            .frame(minHeight: 280)

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
        .navigationTitle("Application options")
    }

    // MARK: General

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Data display") {
                    VStack(alignment: .leading, spacing: 8) {
                        secondsRow("Data refresh interval:", value: $refreshInterval)
                        secondsRow(
                            "Data refresh interval when minimized:",
                            value: $refreshIntervalMinimized
                        )
                        Toggle(
                            "Average out transfer speeds to eliminate fluctuations",
                            isOn: $averageSpeeds
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                GroupBox("Add torrent") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            "Prompt for download options when adding a new torrent",
                            isOn: $promptDownloadOptions
                        )
                        Toggle(
                            "Delete a .torrent file after a successful addition",
                            isOn: $deleteTorrentFile
                        )
                        Toggle(
                            "Automatically add torrent links from the clipboard",
                            isOn: $linksFromClipboard
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Misc

    private var miscTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Speed limit menu items") {
                    VStack(alignment: .leading, spacing: 10) {
                        labeledField("Download speeds (KB/s):", text: $speedMenuDown)
                        labeledField("Upload speeds (KB/s):", text: $speedMenuUp)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                Text("The values feed the D: and U: speed menus of the status bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Rows

    private func secondsRow(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label)
            TextField("", value: value, format: .number)
                .frame(width: 70)
            Text("seconds")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 180, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: Save

    private func ok() {
        AppSettings.refreshInterval = refreshInterval
        AppSettings.refreshIntervalMinimized = refreshIntervalMinimized
        AppSettings.averageSpeeds = averageSpeeds
        AppSettings.promptDownloadOptions = promptDownloadOptions
        AppSettings.deleteTorrentFile = deleteTorrentFile
        AppSettings.linksFromClipboard = linksFromClipboard
        AppSettings.speedMenuDown = speedMenuDown
        AppSettings.speedMenuUp = speedMenuUp
        dismiss()
    }
}
