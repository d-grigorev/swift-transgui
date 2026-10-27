import SwiftUI
import TransGUICore

/// Bottom strip: connection state, total speeds (with limits), free space.
/// The D:/U: panels open the speed-limit menu on right-click, like the
/// reference app's status bar.
struct StatusBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            panel {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(model.statusCaption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(minWidth: 200)
            .layoutPriority(1)

            Divider().frame(height: 18)

            speedPanel(direction: .down) {
                Text(downloadText)
                    .monospacedDigit()
            }
            .frame(minWidth: 120)

            Divider().frame(height: 18)

            speedPanel(direction: .up) {
                Text(uploadText)
                    .monospacedDigit()
            }
            .frame(minWidth: 120)

            Divider().frame(height: 18)

            panel {
                Text(freeText)
                    .monospacedDigit()
            }
            .frame(minWidth: 90)

            Spacer(minLength: 0)
        }
        .font(.callout)
        .lineLimit(1)
        .frame(height: 24)
        .background(.quaternary.opacity(0.3))
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) {
            content()
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }

    /// A speed panel with the right-click speed-limit menu attached while
    /// connected (no menu while disconnected).
    @ViewBuilder
    private func speedPanel<Content: View>(
        direction: AppModel.SpeedLimitDirection,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        let base = panel(content)
        if model.phase.isConnected {
            base.contextMenu {
                speedLimitMenu(direction)
            }
        } else {
            base
        }
    }

    /// `Unlimited` + the presets from Application options (Misc), the
    /// current limit checked — the reference app's speed popup.
    @ViewBuilder
    private func speedLimitMenu(_ direction: AppModel.SpeedLimitDirection) -> some View {
        let limit = currentLimit(direction)

        Toggle("Unlimited", isOn: Binding(
            get: { limit == nil },
            set: { enabled in
                if enabled {
                    Task { await model.setGlobalSpeedLimit(direction, kbps: nil) }
                }
            }
        ))

        let presets = presets(for: direction)
        if !presets.isEmpty {
            Divider()
            ForEach(presets, id: \.self) { value in
                Toggle("\(value) KB/s", isOn: Binding(
                    get: { limit == value },
                    set: { enabled in
                        if enabled {
                            Task {
                                await model.setGlobalSpeedLimit(direction, kbps: value)
                            }
                        }
                    }
                ))
            }
        }
    }

    /// The active global limit in KB/s (nil = unlimited).
    private func currentLimit(
        _ direction: AppModel.SpeedLimitDirection
    ) -> Int? {
        let session = model.session
        switch direction {
        case .down:
            return session?.speedLimitDownEnabled == true ? session?.speedLimitDown : nil
        case .up:
            return session?.speedLimitUpEnabled == true ? session?.speedLimitUp : nil
        }
    }

    /// Parsed presets, plus the live limit so it stays checkable (like the
    /// reference app, which inserts the current value into the list).
    private func presets(
        for direction: AppModel.SpeedLimitDirection
    ) -> [Int] {
        let list = direction == .down ? AppSettings.speedMenuDown : AppSettings.speedMenuUp
        var values = Set(AppSettings.speedPresets(list))
        if let limit = currentLimit(direction) {
            values.insert(limit)
        }
        return values.sorted()
    }

    private var statusColor: Color {
        switch model.phase {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        case .idle: .secondary
        }
    }

    private var downloadText: String {
        let limit = Fmt.speedLimit(kilobytesPerSecond: currentLimit(.down))
        return "D: \(Fmt.speed(model.totalDownSpeed) ?? "0 B/s") (\(limit)/s)"
    }

    private var uploadText: String {
        let limit = Fmt.speedLimit(kilobytesPerSecond: currentLimit(.up))
        return "U: \(Fmt.speed(model.totalUpSpeed) ?? "0 B/s") (\(limit)/s)"
    }

    private var freeText: String {
        guard let freeSpace = model.freeSpace else { return "Free: -" }
        return "Free: \(Fmt.size(freeSpace))"
    }
}
