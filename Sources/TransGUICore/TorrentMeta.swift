import Foundation

/// Metadata read from a `.torrent` file (bencode) for the add-torrent flows:
/// the torrent's name and its tracker list (used for the duplicate-torrent
/// "update trackers" merge).
public enum TorrentMeta {
    /// Extracted metainfo. `trackers` is the flattened `announce-list`
    /// (tier order preserved, duplicates removed); falls back to `announce`
    /// when `announce-list` is absent.
    public struct Meta: Equatable, Sendable {
        public let name: String?
        public let trackers: [String]
        public let infoHashHex: String?
    }

    /// Parses the top level of a .torrent file. Returns nil when the data is
    /// not bencode or has no dictionary root.
    public static func parse(metainfo data: Data) -> Meta? {
        guard let root = try? Bencode.parse(data), case .dictionary = root else {
            return nil
        }
        var trackers: [String] = []
        var seen = Set<String>()
        func addTracker(_ url: String) {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            trackers.append(trimmed)
        }

        if let tiers = root["announce-list"]?.listValue {
            for tier in tiers {
                guard let urls = tier.listValue else { continue }
                for url in urls {
                    if let s = url.stringValue {
                        addTracker(s)
                    }
                }
            }
        }
        if trackers.isEmpty, let announce = root["announce"]?.stringValue {
            addTracker(announce)
        }

        return Meta(
            name: root["info"]?["name"]?.stringValue,
            trackers: trackers,
            infoHashHex: Bencode.infoHash(ofMetainfo: data)
        )
    }
}

/// Magnet link helpers: infohash and tracker extraction (`tr` parameters).
public enum MagnetLink {
    /// The `xt=urn:btih:<hash>` infohash (lowercased hex, or base32 decoded
    /// to hex), nil when absent or malformed.
    public static func infoHash(_ link: String) -> String? {
        for value in parameterValues("xt", in: link) {
            let lower = value.lowercased()
            guard lower.hasPrefix("urn:btih:") else { continue }
            let hash = String(value.dropFirst("urn:btih:".count))
            if isHexHash(hash) {
                return hash.lowercased()
            }
            if hash.count == 32, let decoded = base32Decode(hash) {
                return decoded.map { String(format: "%02x", $0) }.joined()
            }
        }
        return nil
    }

    /// Tracker URLs from the `tr` parameters, in order.
    public static func trackers(_ link: String) -> [String] {
        parameterValues("tr", in: link).filter { !$0.isEmpty }
    }

    /// Whether the text is a bare 40-character hexadecimal infohash (the
    /// add-link dialog converts those to magnet links).
    public static func isInfoHash(_ text: String) -> Bool {
        isHexHash(text)
    }

    /// Wraps a bare infohash into a magnet link.
    public static func magnetFromInfoHash(_ hash: String) -> String {
        "magnet:?xt=urn:btih:\(hash)"
    }

    // MARK: - Helpers

    private static func isHexHash(_ text: String) -> Bool {
        guard text.count == 40 else { return false }
        return text.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
            || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0)
            || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains($0)
        }
    }

    /// Values of a query parameter in a magnet URI, percent-decoded.
    private static func parameterValues(_ name: String, in link: String) -> [String] {
        guard let range = link.range(of: "?") else { return [] }
        var result: [String] = []
        for pair in link[range.upperBound...].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].lowercased() == name.lowercased() else {
                continue
            }
            let raw = String(parts[1])
            result.append(raw.removingPercentEncoding ?? raw)
        }
        return result
    }

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    private static func base32Decode(_ text: String) -> [UInt8]? {
        var bits = 0
        var value = 0
        var bytes: [UInt8] = []
        for character in text.uppercased() {
            guard let index = base32Alphabet.firstIndex(of: character) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return bytes.count == 20 ? bytes : nil
    }
}
