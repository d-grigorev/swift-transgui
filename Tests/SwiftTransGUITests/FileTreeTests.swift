import Foundation
import Testing
import TransGUICore
@testable import SwiftTransGUI

/// File tree building, collapsing, sorting and template matching
/// (shared by the Files tab and the add-torrent dialog).
@Suite("File tree")
struct FileTreeTests {
    private let files: [TorrentFile] = try! JSONDecoder().decode(
        [TorrentFile].self,
        from: Data(
            """
            [
              {"name":"show/a/ep1.mkv","length":300,"bytesCompleted":300},
              {"name":"show/a/ep2.mkv","length":100,"bytesCompleted":50},
              {"name":"show/b/ep1.avi","length":200,"bytesCompleted":0},
              {"name":"top.txt","length":50,"bytesCompleted":50}
            ]
            """.utf8)
    )
    private let priorities = [1, 0, -1, 0]
    private let wanted = [1, 1, 0, 1]

    private func rows(
        collapsed: Set<String> = [],
        sortBy: [KeyPathComparator<FileTreeRow>] = []
    ) -> [FileTreeRow] {
        FileTree.rows(
            files: files, priorities: priorities, wanted: wanted,
            collapsed: collapsed, sortBy: sortBy)
    }

    @Test("Tree structure, indentation and aggregates")
    func structure() {
        let rows = rows()
        // Roots: folder "show", file "top.txt" — daemon order preserved.
        #expect(rows.map(\.id) == [
            "show", "show/a", "show/a/ep1.mkv", "show/a/ep2.mkv",
            "show/b", "show/b/ep1.avi", "top.txt",
        ])
        #expect(rows.map(\.depth) == [0, 1, 2, 2, 1, 2, 0])
        #expect(rows.filter(\.isFolder).count == 3)

        let show = rows[0]
        #expect(show.size == 600)  // folders a (400) + b (200); top.txt is a root
        #expect(show.done == 350)
        #expect(show.priority == nil)  // mixed below
        let folderA = rows[1]
        #expect(folderA.size == 400)
        #expect(folderA.done == 350)
        #expect(folderA.priority == nil)  // 1 and 0 mixed
        let folderB = rows[4]
        #expect(folderB.size == 200)
        #expect(folderB.priority == -1)  // uniform

        // File rows carry per-file wanted/priority.
        #expect(rows[2].wanted && rows[2].priority == 1)
        #expect(!rows[5].wanted && rows[5].priority == -1)
    }

    @Test("Collapsed folders hide their children")
    func collapsing() {
        let rows = rows(collapsed: ["show/a"])
        #expect(rows.map(\.id) == [
            "show", "show/a", "show/b", "show/b/ep1.avi", "top.txt",
        ])
        // Aggregates of the collapsed folder remain visible.
        #expect(rows[1].size == 400)
    }

    @Test("Sort applies recursively; inverting flips every level")
    func sorting() {
        // Size descending: (650 show, 50 top) / (400 a, 200 b) / (300, 100).
        let bySizeDesc = rows(sortBy: [KeyPathComparator(\FileTreeRow.size, order: .reverse)])
        #expect(bySizeDesc.map(\.id) == [
            "show", "show/a", "show/a/ep1.mkv", "show/a/ep2.mkv",
            "show/b", "show/b/ep1.avi", "top.txt",
        ])

        // Size ascending inverts each level independently (hierarchy intact).
        let bySizeAsc = rows(sortBy: [KeyPathComparator(\FileTreeRow.size)])
        #expect(bySizeAsc.map(\.id) == [
            "top.txt", "show", "show/b", "show/b/ep1.avi",
            "show/a", "show/a/ep2.mkv", "show/a/ep1.mkv",
        ])

        // Name ascending (natural order for this fixture).
        let byName = rows(sortBy: [KeyPathComparator(\FileTreeRow.name)])
        #expect(byName.map(\.id) == [
            "show", "show/a", "show/a/ep1.mkv", "show/a/ep2.mkv",
            "show/b", "show/b/ep1.avi", "top.txt",
        ])

        // Priority ascending: -1 before 0 before 1; mixed folders (nil →
        // Int.max) sort last; the name tie-break keeps equal keys stable.
        let byPriority = rows(sortBy: [KeyPathComparator(\FileTreeRow.prioritySort)])
        #expect(byPriority.map(\.id) == [
            "top.txt", "show", "show/b", "show/b/ep1.avi",
            "show/a", "show/a/ep2.mkv", "show/a/ep1.mkv",
        ])
    }

    @Test("Empty file list yields no rows")
    func empty() {
        #expect(
            FileTree.rows(files: [], priorities: [], wanted: [], collapsed: []).isEmpty)
    }

    @Test("Sort keys")
    func sortKeys() {
        let rows = rows()
        let ep2 = rows.first { $0.id == "show/a/ep2.mkv" }!
        #expect(ep2.percentSort == 0.5)
        let top = rows.first { $0.id == "top.txt" }!
        #expect(top.percentSort == 1.0)
        #expect(top.prioritySort == 0)
        let mixedFolder = rows[0]
        #expect(mixedFolder.prioritySort == Int.max)
    }
}

/// Glob matching for the add dialog's Template field.
@Suite("File templates")
struct FileTemplateTests {
    private let files: [TorrentFile] = try! JSONDecoder().decode(
        [TorrentFile].self,
        from: Data(
            """
            [
              {"name":"season/ep1.mkv","length":1,"bytesCompleted":1},
              {"name":"season/ep2.mp4","length":1,"bytesCompleted":1},
              {"name":"sample.mkv","length":1,"bytesCompleted":1},
              {"name":"tom.jerry.mkv","length":1,"bytesCompleted":1}
            ]
            """.utf8)
    )

    @Test("Empty template matches everything")
    func emptyTemplate() {
        #expect(FileTemplate.matchingIndices("", files: files) == Set(0..<4))
        #expect(FileTemplate.matchingIndices("   ", files: files) == Set(0..<4))
    }

    @Test("Wildcard patterns")
    func wildcards() {
        #expect(FileTemplate.matchingIndices("*.mkv", files: files) == [0, 2, 3])
        #expect(FileTemplate.matchingIndices("*.MP4", files: files) == [1])  // case-insensitive
        #expect(FileTemplate.matchingIndices("tom*jerry*", files: files) == [3])
        #expect(FileTemplate.matchingIndices("ep?.mp4", files: files) == [1])
        #expect(FileTemplate.matchingIndices("*.mkv *.mp4", files: files) == Set(0..<4))
        #expect(FileTemplate.matchingIndices("*.avi", files: files).isEmpty)
    }
}
