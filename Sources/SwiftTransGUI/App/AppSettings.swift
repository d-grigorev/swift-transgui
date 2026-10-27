import Foundation

/// UserDefaults-backed application settings (the "Application options"
/// dialog plus the view toggles from the View menu). Keys mirror the
/// reference app's meaning; the storage is our own.
enum AppSettings {
    /// `UserDefaults.standard` (a computed accessor keeps the type free of
    /// shared mutable static state under Swift 6 strict concurrency).
    private static var defaults: UserDefaults { .standard }

    // MARK: General

    /// Key of the data refresh interval (seconds, 1...999, default 5).
    static let refreshIntervalKey = "RefreshInterval"

    /// Polling interval in seconds. Drives `AppModel`'s refresh loop.
    static var refreshInterval: Int {
        get { clamped(defaults.object(forKey: refreshIntervalKey) as? Int ?? 5, 1...999) }
        set { defaults.set(clamped(newValue, 1...999), forKey: refreshIntervalKey) }
    }

    /// Refresh interval while the window is minimized (stored only).
    static var refreshIntervalMinimized: Int {
        get { clamped(defaults.object(forKey: "RefreshIntervalMinimized") as? Int ?? 5, 1...999) }
        set { defaults.set(clamped(newValue, 1...999), forKey: "RefreshIntervalMinimized") }
    }

    /// Average out transfer speeds (stored only; the reference defaults on).
    static var averageSpeeds: Bool {
        get { defaults.object(forKey: "AverageSpeeds") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "AverageSpeeds") }
    }

    /// Ask for download options when adding a new torrent (wires the M5
    /// add flow: when off, torrents are added directly with the defaults).
    static var promptDownloadOptions: Bool {
        get { defaults.object(forKey: "PromptDownloadOptions") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "PromptDownloadOptions") }
    }

    /// Delete the .torrent file after a successful addition (stored only).
    static var deleteTorrentFile: Bool {
        get { defaults.object(forKey: "DeleteTorrentFile") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "DeleteTorrentFile") }
    }

    /// Automatically add torrent links from the clipboard (stored only).
    static var linksFromClipboard: Bool {
        get { defaults.object(forKey: "LinksFromClipboard") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "LinksFromClipboard") }
    }

    // MARK: Misc (speed limit menus)

    static let defaultSpeeds = "100, 500, 1000, 2000, 5000"

    /// Comma-separated download speed presets for the status-bar menu.
    static var speedMenuDown: String {
        get { defaults.string(forKey: "SpeedMenuDown") ?? defaultSpeeds }
        set { defaults.set(newValue, forKey: "SpeedMenuDown") }
    }

    /// Comma-separated upload speed presets for the status-bar menu.
    static var speedMenuUp: String {
        get { defaults.string(forKey: "SpeedMenuUp") ?? defaultSpeeds }
        set { defaults.set(newValue, forKey: "SpeedMenuUp") }
    }

    /// Parse a comma-separated KB/s list into sorted, unique, non-negative
    /// values (the reference drops anything that is not a number).
    static func speedPresets(_ list: String) -> [Int] {
        var values = Set<Int>()
        for piece in list.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" }) {
            if let value = Int(piece), value >= 0 {
                values.insert(value)
            }
        }
        return values.sorted()
    }

    // MARK: View toggles

    static var showFilterPane: Bool {
        get { defaults.object(forKey: "ShowFilterPane") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ShowFilterPane") }
    }

    static var showInfoPane: Bool {
        get { defaults.object(forKey: "ShowInfoPane") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ShowInfoPane") }
    }

    static var showStatusBar: Bool {
        get { defaults.object(forKey: "ShowStatusBar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ShowStatusBar") }
    }

    // MARK: Helpers

    private static func clamped(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
