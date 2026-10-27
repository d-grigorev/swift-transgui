import CryptoKit
import Foundation

/// Errors thrown while decoding bencode data.
public enum BencodeError: Error, Equatable, Sendable {
    case truncated
    case malformed
}

/// A decoded bencode value (BEP 3). Byte strings keep their raw bytes;
/// dictionary keys are searched case-sensitively via the string subscript.
public indirect enum BencodeValue: Equatable, Sendable {
    case integer(Int64)
    case bytes(Data)
    case list([BencodeValue])
    case dictionary([BencodeEntry])

    /// First value stored under `key` in a dictionary, else nil.
    public subscript(key: String) -> BencodeValue? {
        guard case .dictionary(let entries) = self else { return nil }
        let keyBytes = Data(key.utf8)
        return entries.first { $0.key == keyBytes }?.value
    }

    public var bytesValue: Data? {
        if case .bytes(let data) = self { return data }
        return nil
    }

    /// Byte string decoded as UTF-8 (lossy); nil for non-byte values.
    public var stringValue: String? {
        guard let data = bytesValue else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public var listValue: [BencodeValue]? {
        if case .list(let items) = self { return items }
        return nil
    }
}

/// One `key`/`value` pair of a bencode dictionary.
public struct BencodeEntry: Equatable, Sendable {
    public let key: Data
    public let value: BencodeValue

    public init(key: Data, value: BencodeValue) {
        self.key = key
        self.value = value
    }
}

/// Minimal bencode decoder — enough to read .torrent metadata (name,
/// trackers, info dict) without a torrent library.
public enum Bencode {
    /// Decodes one complete bencoded document; trailing bytes are ignored.
    public static func parse(_ data: Data) throws -> BencodeValue {
        var scanner = Scanner(bytes: [UInt8](data))
        return try scanner.value()
    }

    /// SHA-1 (lowercase hex) of the raw bencoded `info` dictionary — the
    /// torrent's infohash. Re-encodes nothing: the exact byte range of the
    /// `info` value inside `data` is hashed.
    public static func infoHash(ofMetainfo data: Data) -> String? {
        var scanner = Scanner(bytes: [UInt8](data))
        guard let range = try? scanner.dictionaryValueRange(forKey: "info"),
            !range.isEmpty
        else { return nil }
        // The scanner's range is 0-based; re-base it for (possibly sliced) Data.
        let base = data.startIndex
        let slice = data[(base + range.lowerBound)..<(base + range.upperBound)]
        let digest = Insecure.SHA1.hash(data: slice)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Scanner

    private struct Scanner {
        let bytes: [UInt8]
        var pos = 0

        private static let chI = UInt8(ascii: "i")
        private static let chL = UInt8(ascii: "l")
        private static let chD = UInt8(ascii: "d")
        private static let chE = UInt8(ascii: "e")
        private static let chColon = UInt8(ascii: ":")

        mutating func value() throws -> BencodeValue {
            guard pos < bytes.count else { throw BencodeError.truncated }
            switch bytes[pos] {
            case Self.chI:
                return .integer(try integer())
            case Self.chL:
                pos += 1
                var items: [BencodeValue] = []
                while try peek() != Self.chE {
                    items.append(try value())
                }
                pos += 1
                return .list(items)
            case Self.chD:
                pos += 1
                var entries: [BencodeEntry] = []
                while try peek() != Self.chE {
                    let key = try byteString()
                    entries.append(BencodeEntry(key: key, value: try value()))
                }
                pos += 1
                return .dictionary(entries)
            default:
                return .bytes(try byteString())
            }
        }

        /// Byte range of a top-level dictionary value (e.g. the `info` dict),
        /// for hashing the exact original bytes.
        mutating func dictionaryValueRange(forKey key: String) throws -> Range<Int>? {
            guard pos < bytes.count, bytes[pos] == Self.chD else { return nil }
            pos += 1
            let keyBytes = Data(key.utf8)
            while try peek() != Self.chE {
                let entryKey = try byteString()
                let start = pos
                try skipValue()
                if entryKey == keyBytes {
                    return start..<pos
                }
            }
            return nil
        }

        private mutating func skipValue() throws {
            guard pos < bytes.count else { throw BencodeError.truncated }
            switch bytes[pos] {
            case Self.chI:
                _ = try integer()
            case Self.chL, Self.chD:
                pos += 1
                while try peek() != Self.chE {
                    try skipValue()
                }
                pos += 1
            default:
                _ = try byteString()
            }
        }

        private mutating func integer() throws -> Int64 {
            pos += 1  // 'i'
            let start = pos
            while pos < bytes.count, bytes[pos] != Self.chE {
                pos += 1
            }
            guard pos < bytes.count,
                let number = Int64(String(decoding: bytes[start..<pos], as: UTF8.self))
            else { throw BencodeError.malformed }
            pos += 1  // 'e'
            return number
        }

        private mutating func byteString() throws -> Data {
            let start = pos
            while pos < bytes.count, bytes[pos] != Self.chColon {
                pos += 1
            }
            guard pos < bytes.count,
                let length = Int(String(decoding: bytes[start..<pos], as: UTF8.self)),
                length >= 0
            else { throw BencodeError.malformed }
            pos += 1  // ':'
            guard pos + length <= bytes.count else { throw BencodeError.truncated }
            let data = Data(bytes[pos..<(pos + length)])
            pos += length
            return data
        }

        private func peek() throws -> UInt8 {
            guard pos < bytes.count else { throw BencodeError.truncated }
            return bytes[pos]
        }
    }
}
