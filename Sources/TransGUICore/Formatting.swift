import Foundation

/// Human-readable value formatting, mirroring the reference app's conventions:
/// sizes use `b / KB / MB / GB / TB` with a space, speeds add `/s`,
/// ETA is rounded coarsely (`3dh, 20m`), dates show relative "from now" values.
public enum Fmt {
    // MARK: Sizes

    public static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "?" }
        return size(bytes)
    }

    public static func size(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "?" }
        if bytes < 1024 {
            return "\(bytes) b"
        }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        // Start in KB so the unit label always matches the value's magnitude
        // (the value begins in bytes — indexing from bytes shifted every
        // label by one unit: 7.1 GB showed up as "7.1 TB").
        var value = Double(bytes) / 1024
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return "\(number(value)) \(units[index])"
    }

    /// Speed in bytes/sec; `nil` when the torrent is idle (cells render blank).
    public static func speed(_ bytesPerSecond: Int64) -> String? {
        guard bytesPerSecond > 0 else { return nil }
        return size(bytesPerSecond) + "/s"
    }

    /// Server-side speed limit text: `100 KB/s` or `Unlimited`.
    public static func speedLimit(kilobytesPerSecond: Int?) -> String {
        guard let kbps = kilobytesPerSecond, kbps > 0 else { return "Unlimited" }
        return size(Int64(kbps) * 1024)
    }

    // MARK: Numbers

    private static func number(_ value: Double) -> String {
        if value < 100 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.0f", value)
    }

    // MARK: ETA

    /// Formats seconds like `12s`, `45m`, `3h, 20m`, `5d`; `nil` when unknown.
    /// Longer times are rounded (5 min steps above 30 min, 1 h steps above 2 h).
    public static func eta(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0, seconds < 10_000_000 else { return nil }
        var s = seconds
        if s > 1800 {
            s = ((s + 150) / 300) * 300
        }
        if s > 7200 {
            s = ((s + 1800) / 3600) * 3600
        }
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if d > 0 {
            return h > 0 ? "\(d)d, \(h)h" : "\(d)d"
        }
        if h > 0 {
            return m > 0 ? "\(h)h, \(m)m" : "\(h)h"
        }
        if m > 0 {
            return "\(m)m"
        }
        return "\(sec)s"
    }

    // MARK: Ratio

    /// Ratio with three decimals; `∞` for infinite, blank for unknown/negative.
    public static func ratio(_ uploadRatio: Double?) -> String {
        guard let r = uploadRatio else { return "" }
        if r.isNaN { return "" }
        if r < 0 { return "" }
        if r.isInfinite || r > 1_000_000 { return "∞" }
        return String(format: "%.3f", r)
    }

    // MARK: Percent

    public static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", max(0, min(1, fraction)) * 100)
    }

    // MARK: Dates

    /// Relative time like `3d, 5h`, `5h, 20m`, `20m`, `just now`.
    public static func relativeTime(unix: Double?) -> String {
        guard let unix, unix > 0 else { return "-" }
        let delta = Date().timeIntervalSince1970 - unix
        if delta < 0 {
            return absolute(unix: unix)
        }
        if delta < 60 {
            return "just now"
        }
        let minutes = Int(delta / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let restMinutes = minutes % 60
        if hours < 24 {
            return restMinutes > 0 ? "\(hours)h, \(restMinutes)m" : "\(hours)h"
        }
        let days = hours / 24
        let restHours = hours % 24
        return restHours > 0 ? "\(days)d, \(restHours)h" : "\(days)d"
    }

    /// Absolute local date/time, used for tooltips.
    public static func absolute(unix: Double?) -> String {
        guard let unix, unix > 0 else { return "-" }
        let date = Date(timeIntervalSince1970: unix)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Duration like `1h, 25m` (used for seeding time).
    public static func duration(_ seconds: Int64?) -> String {
        guard let seconds, seconds > 0 else { return "-" }
        let s = Int(seconds)
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        if d > 0 { return h > 0 ? "\(d)d, \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h, \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
