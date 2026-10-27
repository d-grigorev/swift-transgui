import AppKit
import SwiftUI
import TransGUICore

/// "Add new torrent" dialog: destination folder with history, file template,
/// "Save as" rename, peer limit and the torrent contents tree with wanted
/// checkboxes — mirroring the reference app's add-torrent form.
///
/// The torrent is already on the server (added paused); OK applies the
/// options, Cancel removes the paused torrent again.
struct AddTorrentSheet: View {
    let state: AddTorrentSheetState

    @Environment(AppModel.self) private var model

    @State private var destination: String
    @State private var template = ""
    @State private var saveAs: String
    @State private var peerLimit: Int
    @State private var start: Bool
    @State private var checked: Set<Int>
    @State private var collapsed: Set<String> = []
    @State private var freeSpaceText = ""
    @State private var errorText: String?

    init(state: AddTorrentSheetState) {
        self.state = state
        _destination = State(initialValue: state.destination)
        _saveAs = State(initialValue: AddTorrentNaming.sanitized(state.originalName))
        _peerLimit = State(initialValue: state.defaultPeerLimit)
        _start = State(initialValue: AddTorrentDefaults.startTorrentOnAdd)
        _checked = State(initialValue: Set(state.files.indices))
        _template = State(initialValue: AddTorrentDefaults.template(for: state.destination))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldsGrid

            if state.isMagnet {
                Text("The torrent contents will be known when the metadata is downloaded.")
                    .foregroundStyle(.secondary)
            } else {
                contentsGroup
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            bottomBar
        }
        .padding(20)
        .frame(width: 580, height: state.isMagnet ? 250 : 600)
        .navigationTitle("Add new torrent")
        .onAppear {
            applyTemplate()
        }
        .onDisappear {
            // Safety net: if the sheet went away without OK/Cancel (e.g. the
            // window closed the presentation), remove the paused torrent.
            if model.addTorrentSheet?.id == state.id {
                Task { await model.cancelAddTorrent(state) }
            }
        }
        .onChange(of: destination) { _, _ in
            loadRememberedTemplate()
        }
        .onChange(of: template) { _, _ in
            applyTemplate()
        }
        .task(id: destination) {
            // Debounce: typing in the destination field should not fire one
            // RPC per keystroke (the reference app uses a timer too).
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            freeSpaceText = await model.freeSpaceText(at: destination)
        }
    }

    // MARK: Fields

    private var fieldsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Destination folder:")
                HStack(spacing: 4) {
                    TextField("", text: $destination)
                        .textFieldStyle(.roundedBorder)
                    destinationHistoryMenu
                    Button {
                        browse()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Browse folder")
                    Button {
                        AddTorrentDefaults.removeDestination(destination)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete destination folder")
                }
            }

            GridRow {
                Text("Template:")
                TextField("", text: $template)
                    .textFieldStyle(.roundedBorder)
                    .help("for example: *.avi *.mkv tom*jerry*.avi")
            }

            GridRow {
                Text("Save as:")
                TextField("", text: $saveAs)
                    .textFieldStyle(.roundedBorder)
                    .disabled(state.isMagnet)
            }

            GridRow {
                Text("Peer limit:")
                Stepper(value: $peerLimit, in: 1...999) {
                    Text("\(peerLimit)")
                        .monospacedDigit()
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
        }
        .gridColumnAlignment(.trailing)
    }

    private var destinationHistoryMenu: some View {
        Menu {
            if destinationHistory.isEmpty {
                Text("No history")
            } else {
                ForEach(destinationHistory, id: \.self) { folder in
                    Button(folder) {
                        destination = folder
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
        .help("Recent destination folders")
    }

    /// History plus the session download dir (the default destination, which
    /// the reference app also offers in the combo box).
    private var destinationHistory: [String] {
        var folders = AddTorrentDefaults.destinations
        if let dir = model.session?.downloadDir, !dir.isEmpty, !folders.contains(dir) {
            folders.insert(dir, at: 0)
        }
        return folders
    }

    // MARK: Contents

    private var contentsGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Free disk space: \(freeSpaceText.isEmpty ? "-" : freeSpaceText)")
                        .monospacedDigit()
                    Spacer()
                    Button("Select all") {
                        checked = Set(state.files.indices)
                    }
                    Button("Select none") {
                        checked = []
                    }
                }

                Table(visibleRows) {
                    TableColumn("File name") { row in
                        nameCell(row)
                    }
                    .width(min: 220, ideal: 380)

                    TableColumn("Size") { row in
                        HStack {
                            Spacer(minLength: 0)
                            Text(Fmt.size(row.size))
                                .monospacedDigit()
                        }
                    }
                    .width(min: 60, ideal: 80)
                }
                .frame(maxHeight: .infinity)

                Text("Size: \(Fmt.size(selectedSize)) / \(Fmt.size(totalSize))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        } label: {
            Text("Torrent contents")
        }
    }

    @ViewBuilder
    private func nameCell(_ row: FileTreeRow) -> some View {
        HStack(spacing: 4) {
            if row.depth > 0 {
                Color.clear
                    .frame(width: CGFloat(row.depth) * 14, height: 1)
            }
            if row.isFolder {
                Button {
                    if collapsed.contains(row.id) {
                        collapsed.remove(row.id)
                    } else {
                        collapsed.insert(row.id)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed.contains(row.id) ? 0 : 90))
                }
                .buttonStyle(.plain)
            }
            Toggle("", isOn: checkedBinding(row))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(row.id)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            Toggle("Start torrent", isOn: $start)
                .toggleStyle(.checkbox)
                .fontWeight(start ? .regular : .bold)
                .onChange(of: start) { _, newValue in
                    AddTorrentDefaults.startTorrentOnAdd = newValue
                }

            Spacer()

            Button("Cancel") {
                Task { await model.cancelAddTorrent(state) }
            }
            .keyboardShortcut(.cancelAction)

            Button("OK") {
                submit()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .fontWeight(start ? .regular : .bold)
        }
    }

    // MARK: Tree state

    private var visibleRows: [FileTreeRow] {
        let wanted = state.files.indices.map { checked.contains($0) ? 1 : 0 }
        return FileTree.rows(
            files: state.files,
            priorities: [],
            wanted: wanted,
            collapsed: collapsed
        )
    }

    private var selectedSize: Int64 {
        state.files.enumerated().reduce(0) { total, pair in
            checked.contains(pair.offset) ? total + (pair.element.length ?? 0) : total
        }
    }

    private var totalSize: Int64 {
        state.files.reduce(0) { $0 + ($1.length ?? 0) }
    }

    private func checkedBinding(_ row: FileTreeRow) -> Binding<Bool> {
        if let index = row.fileIndex {
            return Binding(
                get: { checked.contains(index) },
                set: { on in
                    if on {
                        checked.insert(index)
                    } else {
                        checked.remove(index)
                    }
                }
            )
        }
        let children = childIndices(of: row.id)
        let allChecked = !children.isEmpty && children.allSatisfy { checked.contains($0) }
        return Binding(
            get: { allChecked },
            set: { on in
                for index in children {
                    if on {
                        checked.insert(index)
                    } else {
                        checked.remove(index)
                    }
                }
            }
        )
    }

    /// File indices located under a folder path (recursively).
    private func childIndices(of folder: String) -> [Int] {
        state.files.indices.filter {
            (state.files[$0].name ?? "").hasPrefix(folder + "/")
        }
    }

    // MARK: Actions

    private func applyTemplate() {
        if template.isEmpty {
            checked = Set(state.files.indices)
        } else {
            checked = FileTemplate.matchingIndices(template, files: state.files)
        }
    }

    private func loadRememberedTemplate() {
        let remembered = AddTorrentDefaults.template(for: destination)
        if remembered != template {
            template = remembered
        } else {
            applyTemplate()
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: destination)
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }

    private func submit() {
        let name = AddTorrentNaming.sanitized(saveAs)
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            errorText = "Invalid name specified."
            return
        }
        var destinationPath = normalizedDestination()
        if destinationPath.isEmpty {
            destinationPath = state.destination
        }
        let options = AddTorrentOptions(
            destination: destinationPath,
            template: template,
            saveAs: name,
            peerLimit: peerLimit,
            start: start,
            checkedFiles: checked
        )
        Task { await model.confirmAddTorrent(state, options: options) }
    }

    /// Collapse duplicate slashes and a trailing slash (reference CorrectPath).
    private func normalizedDestination() -> String {
        var path = destination.trimmingCharacters(in: .whitespaces)
        while path.contains("//") {
            path = path.replacingOccurrences(of: "//", with: "/")
        }
        if path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
