import AppKit
import SwiftUI
import TransGUICore

/// "Torrent properties" dialog: General (speed limits, peer limit, seed
/// ratio and idle-seeding overrides) and Advanced (tracker list) tabs,
/// mirroring the reference app's properties form.
///
/// The values are read from the first selected torrent; OK applies them to
/// the whole selection via one `torrent-set`.
struct TorrentPropertiesSheet: View {
    let state: PropertiesSheetState

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var downloadLimited: Bool
    @State private var downloadLimit: Int
    @State private var uploadLimited: Bool
    @State private var uploadLimit: Int
    @State private var peerLimit: Int
    @State private var ratioState: TriState
    @State private var seedRatioLimit: Double
    @State private var idleState: TriState
    @State private var seedIdleLimit: Int
    @State private var trackersText: String

    init(state: PropertiesSheetState) {
        self.state = state
        _downloadLimited = State(initialValue: state.downloadLimited)
        _downloadLimit = State(initialValue: max(0, state.downloadLimit))
        _uploadLimited = State(initialValue: state.uploadLimited)
        _uploadLimit = State(initialValue: max(0, state.uploadLimit))
        _peerLimit = State(initialValue: state.peerLimit)
        _ratioState = State(initialValue: TriState(mode: state.seedRatioMode))
        _seedRatioLimit = State(initialValue: max(0, state.seedRatioLimit))
        _idleState = State(initialValue: TriState(mode: state.seedIdleMode))
        _seedIdleLimit = State(initialValue: state.seedIdleLimit)
        _trackersText = State(
            initialValue: state.trackers.compactMap(\.announce).joined(separator: "\n")
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            TabView {
                generalTab
                    .tabItem { Text("General") }
                advancedTab
                    .tabItem { Text("Advanced") }
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
        .frame(width: 540, height: 360)
        .navigationTitle(caption)
    }

    /// "Torrent properties - <name>" / "Torrent properties - N torrents".
    private var caption: String {
        if state.ids.count > 1 {
            return "Torrent properties - \(state.ids.count) torrents"
        }
        return "Torrent properties - \(state.name)"
    }

    // MARK: General tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Name:")
                Text(state.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            limitRow(
                title: "Maximum download speed:",
                enabled: $downloadLimited,
                value: $downloadLimit
            )

            limitRow(
                title: "Maximum upload speed:",
                enabled: $uploadLimited,
                value: $uploadLimit
            )

            HStack {
                Text("Peer limit:")
                Spacer(minLength: 0)
                Stepper(value: $peerLimit, in: 1...999) {
                    Text("\(peerLimit)")
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            }

            HStack {
                TriStateCheckbox(title: "Seed ratio:", state: $ratioState)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    TextField("", value: $seedRatioLimit, format: ratioFormat)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                    Stepper(value: $seedRatioLimit, in: 0...9999, step: 0.1) {
                        EmptyView()
                    }
                    .labelsHidden()
                }
                .disabled(ratioState != .on)
            }

            HStack {
                TriStateCheckbox(title: "Stop seeding when inactive for:", state: $idleState)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    TextField("", value: $seedIdleLimit, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                    Stepper(value: $seedIdleLimit, in: 1...999999) {
                        EmptyView()
                    }
                    .labelsHidden()
                }
                .disabled(idleState != .on)
                Text("minutes")
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var ratioFormat: FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(0...1))
    }

    private func limitRow(
        title: String,
        enabled: Binding<Bool>,
        value: Binding<Int>
    ) -> some View {
        HStack {
            Toggle(title, isOn: enabled)
                .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Stepper(value: value, in: 0...999999, step: 10) {
                    EmptyView()
                }
                .labelsHidden()
            }
            .disabled(!enabled.wrappedValue)
            Text("KB/s")
                .frame(width: 40, alignment: .leading)
        }
    }

    // MARK: Advanced tab

    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trackers:")
            TextEditor(text: $trackersText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
    }

    // MARK: Submit

    private func submit() {
        let options = PropertiesOptions(
            downloadLimited: downloadLimited,
            downloadLimit: clamp(downloadLimit, 0...999999),
            uploadLimited: uploadLimited,
            uploadLimit: clamp(uploadLimit, 0...999999),
            peerLimit: clamp(peerLimit, 1...999),
            seedRatioMode: ratioState.mode,
            seedRatioLimit: roundedRatio(seedRatioLimit),
            seedIdleMode: idleState.mode,
            seedIdleLimit: clamp(seedIdleLimit, 1...999999),
            trackersText: trackersText
        )
        Task { await model.applyProperties(state, options: options) }
    }

    private func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private func roundedRatio(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return Double((value * 10).rounded()) / 10
    }
}

// MARK: - Tri-state checkbox

/// Value of a tri-state checkbox: checked (override), mixed-grey (follow
/// the global settings) and unchecked (unlimited) — the reference's
/// AllowGrayed checkboxes use the same three states.
private enum TriState: Equatable {
    case on
    case mixed
    case off

    init(mode: Int) {
        switch mode {
        case 1: self = .on
        case 2: self = .off
        default: self = .mixed
        }
    }

    /// tr_ratiolimit / tr_inactivelimit encoding.
    var mode: Int {
        switch self {
        case .on: 1
        case .mixed: 0
        case .off: 2
        }
    }

    init(nsState: NSControl.StateValue) {
        switch nsState {
        case .on: self = .on
        case .mixed: self = .mixed
        default: self = .off
        }
    }

    var nsState: NSControl.StateValue {
        switch self {
        case .on: .on
        case .mixed: .mixed
        case .off: .off
        }
    }
}

/// NSButton-backed three-state checkbox (SwiftUI's `Toggle` only models
/// two states). Clicking cycles on → mixed → off → on.
private struct TriStateCheckbox: NSViewRepresentable {
    let title: String
    @Binding var state: TriState

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: title,
            target: context.coordinator,
            action: #selector(Coordinator.click(_:))
        )
        button.setButtonType(.switch)
        button.state = state.nsState
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        if button.title != title {
            button.title = title
        }
        if TriState(nsState: button.state) != state {
            button.state = state.nsState
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: TriStateCheckbox

        init(parent: TriStateCheckbox) {
            self.parent = parent
        }

        @MainActor
        @objc func click(_ sender: NSButton) {
            let next: TriState
            switch parent.state {
            case .on: next = .mixed
            case .mixed: next = .off
            case .off: next = .on
            }
            parent.state = next
            // AppKit may have flipped the button itself; pin our cycle.
            sender.state = next.nsState
        }
    }
}
