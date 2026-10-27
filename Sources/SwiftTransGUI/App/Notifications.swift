import Foundation
import UserNotifications

/// Download-complete notifications (`UNUserNotificationCenter`).
///
/// Notifications only work inside a real .app bundle: the bundle identifier
/// (`ru.dgreenday.swifttransgui`) comes from `Scripts/Info.plist`, and
/// `UNUserNotificationCenter.current()` raises when the process has no
/// bundle proxy (e.g. `swift run`), so every entry point is guarded and
/// degrades silently.
enum DownloadNotifier {
    private static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Ask for notification permission once (called on connect). Only asked
    /// while the status is still `notDetermined`; denied/unavailable →
    /// silently skipped.
    static func requestAuthorization() {
        guard isAvailable else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Post "'<name>' has finished downloading".
    static func postDownloadComplete(name: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = "'\(name)' has finished downloading"
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in
            // Best effort; a failed post must not disturb the poll loop.
        }
    }
}
