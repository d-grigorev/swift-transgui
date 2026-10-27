import Foundation
import TransGUICore

// MARK: - Tree model

/// A flattened file-tree row (one folder or one file). Shared by the Files
/// tab and the add-torrent dialog's contents view.
struct FileTreeRow: Identifiable {
    /// Full path (folder path, or the file's path within the torrent).
    let id: String
    let depth: Int
    let isFolder: Bool
    let name: String
    /// Index into the torrent's file list (`nil` for folders).
    let fileIndex: Int?
    let size: Int64
    let done: Int64
    let wanted: Bool
    /// Priority shared by every file below (`nil` = mixed or unknown).
    let priority: Int?

    /// Sort key for the `%` column (`-1` when the size is unknown).
    var percentSort: Double {
        guard size > 0 else { return -1 }
        return Double(done) / Double(size)
    }

    /// Sort key for the `Priority` column (skip < low < normal < high;
    /// mixed/unknown sorts last).
    var prioritySort: Int {
        priority ?? Int.max
    }
}

/// Folder node of the file tree (a class: the tree is recursive).
private final class FolderNode {
    let name: String
    let path: String
    var children: [FileNode] = []
    var size: Int64 = 0
    var done: Int64 = 0
    var priority: Int?

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

private enum FileNode {
    case folder(FolderNode)
    case file(Int)
}

/// Bounds-checked view of the file list arrays (they can differ in length
/// if the daemon answers with a partial snapshot).
struct FileContext {
    let files: [TorrentFile]
    let priorities: [Int]
    let wanted: [Int]

    func name(_ index: Int) -> String {
        guard index < files.count else { return "?" }
        return files[index].name ?? "?"
    }

    func length(_ index: Int) -> Int64 {
        guard index < files.count else { return 0 }
        return files[index].length ?? 0
    }

    func completed(_ index: Int) -> Int64 {
        guard index < files.count else { return 0 }
        return files[index].bytesCompleted ?? 0
    }

    func priority(_ index: Int) -> Int {
        guard index < priorities.count else { return 0 }
        return priorities[index]
    }

    func isWanted(_ index: Int) -> Bool {
        guard index < wanted.count else { return true }
        return wanted[index] != 0
    }
}

// MARK: - Tree building

/// Builds the indented folder tree of a torrent's file list, preserving the
/// daemon's file order and aggregating size/done/priority per folder.
enum FileTree {
    /// Flattened rows for the given file list. `collapsed` hides the rows
    /// below collapsed folder paths. `sortBy` sorts the children of every
    /// folder recursively (folders participate like file rows; an empty
    /// array keeps the daemon's order).
    static func rows(
        files: [TorrentFile],
        priorities: [Int],
        wanted: [Int],
        collapsed: Set<String>,
        sortBy: [KeyPathComparator<FileTreeRow>] = []
    ) -> [FileTreeRow] {
        guard !files.isEmpty else { return [] }
        let context = FileContext(files: files, priorities: priorities, wanted: wanted)
        var roots = makeRoots(context)
        accumulate(roots, context)
        if !sortBy.isEmpty {
            // Name as the final tie-break keeps repeated re-sorts stable.
            sort(&roots, context: context, by: sortBy + [KeyPathComparator(\FileTreeRow.name)])
        }
        var rows: [FileTreeRow] = []
        flatten(roots, depth: 0, collapsed: collapsed, context: context, into: &rows)
        return rows
    }

    /// Sort every folder's children by the table's sort order. Applied
    /// after `accumulate` (folder aggregates are known then) and before
    /// flattening, so the tree structure and collapse state are preserved.
    private static func sort(
        _ nodes: inout [FileNode],
        context: FileContext,
        by comparators: [KeyPathComparator<FileTreeRow>]
    ) {
        guard !comparators.isEmpty else { return }

        var keyed: [FileTreeRow] = []
        var nodeById: [String: FileNode] = [:]
        for node in nodes {
            let row = sortRow(for: node, context: context)
            keyed.append(row)
            nodeById[row.id] = node
        }
        let sortedRows = keyed.sorted(using: comparators)
        nodes = sortedRows.compactMap { nodeById[$0.id] }

        for node in nodes {
            if case .folder(let folder) = node {
                var children = folder.children
                sort(&children, context: context, by: comparators)
                folder.children = children
            }
        }
    }

    /// A `FileTreeRow`-shaped projection of a node, used only for sorting.
    private static func sortRow(for node: FileNode, context: FileContext) -> FileTreeRow {
        switch node {
        case .folder(let folder):
            return FileTreeRow(
                id: folder.path,
                depth: 0,
                isFolder: true,
                name: folder.name,
                fileIndex: nil,
                size: folder.size,
                done: folder.done,
                wanted: true,
                priority: folder.priority
            )
        case .file(let index):
            let path = context.name(index)
            return FileTreeRow(
                id: path,
                depth: 0,
                isFolder: false,
                name: (path as NSString).lastPathComponent,
                fileIndex: index,
                size: context.length(index),
                done: context.completed(index),
                wanted: context.isWanted(index),
                priority: context.priority(index)
            )
        }
    }

    /// Build the tree from file paths (`name` split on `/`), preserving the
    /// daemon's file order.
    private static func makeRoots(_ context: FileContext) -> [FileNode] {
        var roots: [FileNode] = []
        var folders: [String: FolderNode] = [:]

        func ensureFolder(components: [String]) -> FolderNode? {
            var path = ""
            var parent: FolderNode?
            for component in components {
                path = path.isEmpty ? component : path + "/" + component
                if let existing = folders[path] {
                    parent = existing
                    continue
                }
                let node = FolderNode(name: component, path: path)
                folders[path] = node
                if let parent {
                    parent.children.append(.folder(node))
                } else {
                    roots.append(.folder(node))
                }
                parent = node
            }
            return parent
        }

        for index in 0..<context.files.count {
            let parts = context.name(index).split(separator: "/").map(String.init)
            guard parts.count > 1 else {
                roots.append(.file(index))
                continue
            }
            if let folder = ensureFolder(components: Array(parts.dropLast())) {
                folder.children.append(.file(index))
            } else {
                roots.append(.file(index))
            }
        }
        return roots
    }

    /// Aggregate size, done bytes and the uniform (or mixed) priority of
    /// every folder, bottom-up.
    @discardableResult
    private static func accumulate(
        _ nodes: [FileNode],
        _ context: FileContext
    ) -> (size: Int64, done: Int64, priority: Int?) {
        var size: Int64 = 0
        var done: Int64 = 0
        var priority: Int?
        var seen = false

        func merge(_ value: Int?) {
            if !seen {
                seen = true
                priority = value
            } else if priority != value {
                priority = nil
            }
        }

        for node in nodes {
            switch node {
            case .folder(let folder):
                let aggregate = accumulate(folder.children, context)
                folder.size = aggregate.size
                folder.done = aggregate.done
                folder.priority = aggregate.priority
                size += aggregate.size
                done += aggregate.done
                merge(aggregate.priority)
            case .file(let index):
                size += context.length(index)
                done += context.completed(index)
                merge(context.priority(index))
            }
        }
        return (size, done, priority)
    }

    private static func flatten(
        _ nodes: [FileNode],
        depth: Int,
        collapsed: Set<String>,
        context: FileContext,
        into rows: inout [FileTreeRow]
    ) {
        for node in nodes {
            switch node {
            case .folder(let folder):
                rows.append(
                    FileTreeRow(
                        id: folder.path,
                        depth: depth,
                        isFolder: true,
                        name: folder.name,
                        fileIndex: nil,
                        size: folder.size,
                        done: folder.done,
                        wanted: true,
                        priority: folder.priority
                    )
                )
                if !collapsed.contains(folder.path) {
                    flatten(
                        folder.children,
                        depth: depth + 1,
                        collapsed: collapsed,
                        context: context,
                        into: &rows
                    )
                }
            case .file(let index):
                let path = context.name(index)
                rows.append(
                    FileTreeRow(
                        id: path,
                        depth: depth,
                        isFolder: false,
                        name: (path as NSString).lastPathComponent,
                        fileIndex: index,
                        size: context.length(index),
                        done: context.completed(index),
                        wanted: context.isWanted(index),
                        priority: context.priority(index)
                    )
                )
            }
        }
    }
}

// MARK: - File templates

/// Case-insensitive glob matching (`*` and `?`) for the add dialog's
/// Template field, applied to file basenames like the reference app.
enum FileTemplate {
    /// Indices of files whose basename matches at least one pattern of the
    /// space-separated template. An empty template matches everything.
    static func matchingIndices(_ template: String, files: [TorrentFile]) -> Set<Int> {
        let patterns = template.split(whereSeparator: { $0.isWhitespace })
        guard !patterns.isEmpty else { return Set(files.indices) }
        let matchers = patterns.map { globRegex(String($0)) }
        var result = Set<Int>()
        for (index, file) in files.enumerated() {
            let name = ((file.name ?? "") as NSString).lastPathComponent
            if matchers.contains(where: { $0.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil }) {
                result.insert(index)
            }
        }
        return result
    }

    private static func globRegex(_ glob: String) -> NSRegularExpression {
        var pattern = "^"
        for character in glob {
            switch character {
            case "*":
                pattern += ".*"
            case "?":
                pattern += "."
            default:
                pattern += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        pattern += "$"
        // Patterns come from user input; escaping above makes them safe.
        return (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
            ?? NSRegularExpression()
    }
}
