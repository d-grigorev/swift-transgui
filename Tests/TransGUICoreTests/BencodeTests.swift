import Foundation
import Testing
import TransGUICore

/// Bencode decoding and infohash extraction. The expected hash was computed
/// independently with `shasum -a 1` over the raw `info` dictionary bytes.
@Suite("Bencode and metainfo")
struct BencodeTests {
    /// Minimal valid torrent: single file, one tracker, 20-byte pieces.
    private static let fixture = Data(
        """
        d8:announce35:http://tracker.example.com/announce4:infod6:lengthi42e\
        4:name4:test12:piece lengthi16384e6:pieces20:aaaaaaaaaaaaaaaaaaaaee
        """.utf8)

    @Test("Dictionary and nested values decode")
    func parse() throws {
        let root = try Bencode.parse(Self.fixture)
        #expect(root["announce"]?.stringValue == "http://tracker.example.com/announce")
        #expect(root["info"]?["name"]?.stringValue == "test")
        if case .integer(let length)? = root["info"]?["length"] {
            #expect(length == 42)
        } else {
            Issue.record("info.length is not an integer")
        }
        if case .integer(let pieceLength)? = root["info"]?["piece length"] {
            #expect(pieceLength == 16384)
        } else {
            Issue.record("info.piece length is not an integer")
        }
        #expect(root["nonexistent"] == nil)
    }

    @Test("Garbage is rejected")
    func rejectsNonBencode() {
        #expect(throws: (any Error).self) {
            try Bencode.parse(Data("this is not bencode".utf8))
        }
    }

    @Test("Infohash covers exactly the info dictionary")
    func infoHash() {
        #expect(Bencode.infoHash(ofMetainfo: Self.fixture) == "735be5a657163bf0d2c368b581c9159bc66d9800")
        #expect(Bencode.infoHash(ofMetainfo: Data("nonsense".utf8)) == nil)
    }

    @Test("TorrentMeta flattens trackers and keeps the hash")
    func meta() {
        let meta = TorrentMeta.parse(metainfo: Self.fixture)
        #expect(meta?.name == "test")
        #expect(meta?.trackers == ["http://tracker.example.com/announce"])
        #expect(meta?.infoHashHex == "735be5a657163bf0d2c368b581c9159bc66d9800")
        #expect(TorrentMeta.parse(metainfo: Data("nope".utf8)) == nil)
    }

    @Test("Magnet link helpers")
    func magnets() {
        let hex = "da5c93a1d3b048abab3b7bb74f6a8ff76b7379e8"
        #expect(
            MagnetLink.infoHash("magnet:?xt=urn:btih:\(hex)&dn=x&tr=http://t.example.com/a")
                == hex)
        #expect(
            MagnetLink.infoHash("magnet:?xt=urn:btih:\(hex.uppercased())") == hex)
        // Base32 infohash (RFC 4648, 32 chars) decodes to hex (expected value
        // from python3 base64.b32decode).
        #expect(
            MagnetLink.infoHash("magnet:?xt=urn:btih:ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
                == "00443214c74254b635cf84653a56d7c675be77df")
        #expect(MagnetLink.infoHash("magnet:?xt=urn:btih:short") == nil)

        #expect(
            MagnetLink.trackers("magnet:?xt=urn:btih:\(hex)&tr=http://a.example.com&tr=http://b.example.com")
                == ["http://a.example.com", "http://b.example.com"])

        #expect(MagnetLink.isInfoHash(hex))
        #expect(!MagnetLink.isInfoHash("xyz"))
        #expect(
            MagnetLink.magnetFromInfoHash(hex) == "magnet:?xt=urn:btih:\(hex)")
    }
}
