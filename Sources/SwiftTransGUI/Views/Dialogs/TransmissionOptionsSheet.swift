import SwiftUI
import TransGUICore

/// "Transmission options": the daemon's settings, loaded with `session-get`
/// when the dialog opens and written back with `session-set` on OK (only
/// the keys that actually changed are sent). Mirrors the reference app's
/// daemon options dialog: Download / Network (WAN) / Bandwidth / Queue.
struct TransmissionOptionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TransmissionOptionsDraft
    @State private var errorText: String?
    /// Text of the `port-test` alert (nil = hidden).
    @State private var portAlert: String?
    @State private var testingPort = false

    init(state: TransmissionOptionsSheetState) {
        _draft = State(initialValue: TransmissionOptionsDraft(original: state.original))
    }

    /// Queue controls only exist on RPC >= 14 (the reference hides the tab).
    private var hasQueueTab: Bool { model.rpcVersion >= 14 }

    var body: some View {
        VStack(spacing: 12) {
            TabView {
                downloadTab
                    .tabItem { Text("Download") }
                networkTab
                    .tabItem { Text("Network (WAN)") }
                bandwidthTab
                    .tabItem { Text("Bandwidth") }
                if hasQueueTab {
                    queueTab
                        .tabItem { Text("Queue") }
                }
            }
            .frame(minHeight: 320)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(width: 640)
        .navigationTitle("Transmission options")
        .alert(
            portAlert ?? "",
            isPresented: Binding(
                get: { portAlert != nil },
                set: { if !$0 { portAlert = nil } }
            )
        ) {
            Button("OK") {}
        }
    }

    // MARK: Download

    private var downloadTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Default download folder on remote host:")
                    TextField("", text: $draft.downloadDir)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Add .part extension to incomplete files", isOn: $draft.renamePartialFiles)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        "Directory for incomplete files:",
                        isOn: $draft.incompleteDirEnabled
                    )
                    TextField("", text: $draft.incompleteDir)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!draft.incompleteDirEnabled)
                }

                rightAlignedRow {
                    Toggle("Seed ratio:", isOn: $draft.seedRatioLimited)
                    Spacer(minLength: 12)
                    TextField("", value: $draft.seedRatioLimit, format: .number)
                        .frame(width: 80)
                        .disabled(!draft.seedRatioLimited)
                }

                rightAlignedRow {
                    Toggle(
                        "Stop seeding when inactive for:",
                        isOn: $draft.idleSeedingLimitEnabled
                    )
                    Spacer(minLength: 12)
                    TextField("", value: $draft.idleSeedingLimit, format: .number)
                        .frame(width: 80)
                        .disabled(!draft.idleSeedingLimitEnabled)
                    Text("minutes")
                        .foregroundStyle(.secondary)
                }

                rightAlignedRow {
                    Text("Disk cache size:")
                    Spacer(minLength: 12)
                    TextField("", value: $draft.cacheSizeMb, format: .number)
                        .frame(width: 80)
                    Text("MB")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Network (WAN)

    private var networkTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Incoming port:")
                    TextField("", value: $draft.peerPort, format: .number)
                        .frame(width: 90)
                        .disabled(draft.peerPortRandomOnStart)
                    Toggle(
                        "Pick random port on Transmission launch",
                        isOn: $draft.peerPortRandomOnStart
                    )
                }

                HStack(spacing: 16) {
                    Button("Test port", action: testPort)
                        .disabled(testingPort)
                    Toggle("Enable port forwarding", isOn: $draft.portForwardingEnabled)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    Text("Encryption:")
                    Picker("", selection: $draft.encryption) {
                        ForEach(TransmissionEncryption.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }

                HStack(spacing: 12) {
                    Text("Global peer limit:")
                    TextField("", value: $draft.peerLimitGlobal, format: .number)
                        .frame(width: 90)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Enable Peer Exchange", isOn: $draft.pexEnabled)
                    Toggle("Enable DHT", isOn: $draft.dhtEnabled)
                    Toggle("Enable Local Peer Discovery", isOn: $draft.lpdEnabled)
                    Toggle("Enable µTP", isOn: $draft.utpEnabled)
                }
                .padding(.leading, 104)

                Toggle("Enable blocklist:", isOn: $draft.blocklistEnabled)
                TextField("", text: $draft.blocklistUrl)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!draft.blocklistEnabled)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Bandwidth

    private var bandwidthTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Global bandwidth settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        rightAlignedRow {
                            Toggle(
                                "Maximum download speed:",
                                isOn: $draft.speedLimitDownEnabled
                            )
                            Spacer(minLength: 12)
                            TextField("", value: $draft.speedLimitDown, format: .number)
                                .frame(width: 80)
                                .disabled(!draft.speedLimitDownEnabled)
                            Text("KB/s").foregroundStyle(.secondary)
                        }
                        rightAlignedRow {
                            Toggle(
                                "Maximum upload speed:",
                                isOn: $draft.speedLimitUpEnabled
                            )
                            Spacer(minLength: 12)
                            TextField("", value: $draft.speedLimitUp, format: .number)
                                .frame(width: 80)
                                .disabled(!draft.speedLimitUpEnabled)
                            Text("KB/s").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                GroupBox("Alternate bandwidth settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        rightAlignedRow {
                            Text("Maximum download speed:")
                            Spacer(minLength: 12)
                            TextField("", value: $draft.altSpeedDown, format: .number)
                                .frame(width: 80)
                            Text("KB/s").foregroundStyle(.secondary)
                        }
                        rightAlignedRow {
                            Text("Maximum upload speed:")
                            Spacer(minLength: 12)
                            TextField("", value: $draft.altSpeedUp, format: .number)
                                .frame(width: 80)
                            Text("KB/s").foregroundStyle(.secondary)
                        }

                        Toggle(
                            "Use alternate bandwidth settings",
                            isOn: $draft.altSpeedEnabled
                        )
                        Toggle(
                            "Apply alternate bandwidth settings automatically",
                            isOn: $draft.altSpeedTimeEnabled
                        )
                        .padding(.leading, 18)

                        if draft.altSpeedTimeEnabled {
                            HStack(spacing: 8) {
                                Text("From:").padding(.leading, 34)
                                TextField("", text: $draft.timeFrom)
                                    .frame(width: 64)
                                Text("to:")
                                TextField("", text: $draft.timeTo)
                                    .frame(width: 64)
                            }
                            .padding(.leading, 18)

                            daysRow.padding(.leading, 18)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The seven day checkboxes in the reference's display order (Mo…Su).
    /// The wire mask follows Transmission's `tr_sched_day`: Sunday = 1<<0
    /// … Saturday = 1<<6.
    private var daysRow: some View {
        HStack(spacing: 10) {
            Text("Days:")
            ForEach(Self.weekDays, id: \.bit) { day in
                Toggle(day.title, isOn: dayBinding(day.bit))
                    .toggleStyle(.checkbox)
            }
            Spacer(minLength: 0)
        }
    }

    private struct WeekDay {
        let title: String
        let bit: Int
    }

    /// Display order Mo…Su with the matching `alt-speed-time-day` bits.
    private static let weekDays: [WeekDay] = [
        WeekDay(title: "Mo", bit: 1 << 1),
        WeekDay(title: "Tu", bit: 1 << 2),
        WeekDay(title: "We", bit: 1 << 3),
        WeekDay(title: "Th", bit: 1 << 4),
        WeekDay(title: "Fr", bit: 1 << 5),
        WeekDay(title: "Sa", bit: 1 << 6),
        WeekDay(title: "Su", bit: 1 << 0),
    ]

    private func dayBinding(_ bit: Int) -> Binding<Bool> {
        Binding(
            get: { draft.dayMask & bit != 0 },
            set: { enabled in
                draft.dayMask = enabled ? draft.dayMask | bit : draft.dayMask & ~bit
            }
        )
    }

    // MARK: Queue

    private var queueTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                rightAlignedRow {
                    Toggle("Download queue size:", isOn: $draft.downloadQueueEnabled)
                    Spacer(minLength: 12)
                    TextField("", value: $draft.downloadQueueSize, format: .number)
                        .frame(width: 80)
                        .disabled(!draft.downloadQueueEnabled)
                }

                rightAlignedRow {
                    Toggle("Upload queue size:", isOn: $draft.seedQueueEnabled)
                    Spacer(minLength: 12)
                    TextField("", value: $draft.seedQueueSize, format: .number)
                        .frame(width: 80)
                        .disabled(!draft.seedQueueEnabled)
                }

                rightAlignedRow {
                    Toggle(
                        "Consider active torrents as stalled when idle for:",
                        isOn: $draft.queueStalledEnabled
                    )
                    .help(
                        "Torrents that are idle for N minutes aren't counted "
                            + "toward the Download queue or Upload queue"
                    )
                    Spacer(minLength: 12)
                    TextField("", value: $draft.queueStalledMinutes, format: .number)
                        .frame(width: 80)
                        .disabled(!draft.queueStalledEnabled)
                    Text("minutes")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    /// `port-test` (read-only) → the reference's success/failure message.
    private func testPort() {
        Task {
            testingPort = true
            let outcome = await model.testIncomingPort()
            testingPort = false
            switch outcome {
            case .open:
                portAlert = "Incoming port tested successfully."
            case .closed:
                portAlert = "Incoming port is closed. Check your firewall settings."
            case .failed(let message):
                errorText = message
            }
        }
    }

    private func ok() {
        let dir = draft.downloadDir.trimmingCharacters(in: .whitespaces)
        guard !dir.isEmpty else {
            errorText = "The downloads directory was not specified."
            return
        }
        draft.downloadDir = dir

        draft.incompleteDir = draft.incompleteDir.trimmingCharacters(in: .whitespaces)
        if draft.incompleteDirEnabled && draft.incompleteDir.isEmpty {
            errorText = "The directory for incomplete files was not specified."
            return
        }

        if draft.altSpeedTimeEnabled {
            guard TransmissionOptionsDraft.minutes(from: draft.timeFrom) != nil else {
                errorText = "The invalid time value was entered."
                return
            }
            guard TransmissionOptionsDraft.minutes(from: draft.timeTo) != nil else {
                errorText = "The invalid time value was entered."
                return
            }
        }

        clamp()
        let applied = draft
        dismiss()
        Task { await model.applyTransmissionOptions(applied) }
    }

    /// Keep the numeric fields inside the reference's spin-edit ranges.
    private func clamp() {
        draft.peerPort = min(65535, max(1, draft.peerPort))
        draft.cacheSizeMb = min(9999, max(0, draft.cacheSizeMb))
        draft.idleSeedingLimit = min(999_999, max(1, draft.idleSeedingLimit))
        draft.seedRatioLimit = min(9999, max(0, draft.seedRatioLimit))
        draft.peerLimitGlobal = min(99_999, max(1, draft.peerLimitGlobal))
        draft.downloadQueueSize = min(999_999, max(1, draft.downloadQueueSize))
        draft.seedQueueSize = min(999_999, max(1, draft.seedQueueSize))
        draft.queueStalledMinutes = min(999_999, max(1, draft.queueStalledMinutes))
        draft.speedLimitDown = min(999_999, max(0, draft.speedLimitDown))
        draft.speedLimitUp = min(999_999, max(0, draft.speedLimitUp))
        draft.altSpeedDown = min(999_999, max(0, draft.altSpeedDown))
        draft.altSpeedUp = min(999_999, max(0, draft.altSpeedUp))
    }

    // MARK: Layout helpers

    /// A row with a leading label/checkbox and a right-aligned control
    /// (the reference's fixed-column layout).
    private func rightAlignedRow<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            content()
        }
    }
}
