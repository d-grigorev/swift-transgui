import SwiftUI
import TransGUICore

/// Function-key equivalents: macOS maps F1…F12 to the private-use
/// characters U+F704…U+F70F (the same scalars AppKit's NSF1FunctionKey…
/// NSF12FunctionKey constants use).
///
/// Note: `keyboardShortcut(_:)` defaults to `.command` modifiers, so the
/// reference's bare keys (F3, Delete, ...) pass `modifiers: []` explicitly.
enum Key {
    static let f2 = KeyEquivalent(Character(UnicodeScalar(0xF705)!))
    static let f3 = KeyEquivalent(Character(UnicodeScalar(0xF706)!))
    static let f4 = KeyEquivalent(Character(UnicodeScalar(0xF707)!))
    static let f6 = KeyEquivalent(Character(UnicodeScalar(0xF709)!))
    static let f7 = KeyEquivalent(Character(UnicodeScalar(0xF70A)!))
    static let f8 = KeyEquivalent(Character(UnicodeScalar(0xF70B)!))
    static let f9 = KeyEquivalent(Character(UnicodeScalar(0xF70C)!))
    static let f11 = KeyEquivalent(Character(UnicodeScalar(0xF70E)!))
    static let f12 = KeyEquivalent(Character(UnicodeScalar(0xF70F)!))
}

@main
struct SwiftTransGUIApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("SwiftTransGUI") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 940, minHeight: 520)
                .task {
                    await model.launch()
                }
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Torrent") {
                Button("Add torrent...") {
                    model.pickTorrentFiles()
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(!model.phase.isConnected)

                Button("Add torrent link...") {
                    model.showAddLinkSheet = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!model.phase.isConnected)

                Divider()

                Button("Start") {
                    Task { await model.start() }
                }
                .keyboardShortcut(Key.f3, modifiers: [])
                .disabled(!model.canAct)

                Button("Force start") {
                    Task { await model.forceStart() }
                }
                .keyboardShortcut(Key.f3, modifiers: .shift)
                .disabled(!model.canForceStart)

                Button("Start all torrents") {
                    Task { await model.startAll() }
                }
                .keyboardShortcut(Key.f3, modifiers: .control)
                .disabled(!model.phase.isConnected)

                Button("Stop") {
                    Task { await model.stop() }
                }
                .keyboardShortcut(Key.f4, modifiers: [])
                .disabled(!model.canAct)

                Button("Stop all torrents") {
                    Task { await model.stopAll() }
                }
                .keyboardShortcut(Key.f4, modifiers: .control)
                .disabled(!model.phase.isConnected)

                Button("Remove") {
                    model.askRemove()
                }
                .keyboardShortcut(.deleteForward, modifiers: [])
                .disabled(!model.canAct)

                Button("Remove torrent and Data") {
                    model.askRemove(asksData: true)
                }
                .keyboardShortcut(.deleteForward, modifiers: .shift)
                .disabled(!model.canRemoveData)

                Divider()

                Menu("Priority") {
                    Button("High") {
                        Task { await model.setBandwidthPriority(priority: 1) }
                    }
                    Button("Normal") {
                        Task { await model.setBandwidthPriority(priority: 0) }
                    }
                    Button("Low") {
                        Task { await model.setBandwidthPriority(priority: -1) }
                    }
                }
                .disabled(!model.canAct)

                Menu("Queue") {
                    Button("Move top") {
                        Task { await model.queueMove(position: .top) }
                    }
                    .keyboardShortcut("1", modifiers: [.control, .shift])

                    Button("Move up") {
                        Task { await model.queueMove(position: .up) }
                    }
                    .keyboardShortcut("1", modifiers: .control)

                    Button("Move down") {
                        Task { await model.queueMove(position: .down) }
                    }
                    .keyboardShortcut("2", modifiers: .control)

                    Button("Move bottom") {
                        Task { await model.queueMove(position: .bottom) }
                    }
                    .keyboardShortcut("2", modifiers: [.control, .shift])
                }
                .disabled(!model.canAct)

                Button("Reannounce (get more peers)") {
                    Task { await model.reannounce() }
                }
                .keyboardShortcut("r", modifiers: .control)
                .disabled(!model.canAct)

                Button("Verify") {
                    model.askVerify()
                }
                .disabled(!model.canAct)

                Button("Set data location...") {
                    model.presentDataLocation()
                }
                .keyboardShortcut(Key.f6, modifiers: [])
                .disabled(!model.canSetLocation)

                Button("Set labels...") {
                    model.presentLabels()
                }
                .keyboardShortcut(Key.f7, modifiers: [])
                .disabled(!model.canSetLabels)

                Button("Rename") {
                    model.presentRename()
                }
                .keyboardShortcut(Key.f2, modifiers: [])
                .disabled(!model.canRename)

                Button("Properties...") {
                    Task { await model.presentProperties() }
                }
                .keyboardShortcut(.return, modifiers: .option)
                .disabled(!model.canAct)

                Divider()

                connectMenu

                Button("Disconnect") {
                    model.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!model.phase.isConnected)
            }

            viewMenu

            toolsMenu
        }
    }

    // MARK: Connect submenu (M6)

    /// Profiles with a checkmark on the current one, then the connections
    /// dialog entry points. ⌘K rides on the current profile's item and
    /// connects to it (the toolbar menu mirrors this submenu).
    private var connectMenu: some View {
        Menu("Connect to Transmission") {
            ForEach(model.profiles) { profile in
                let item = Toggle(profile.displayName, isOn: Binding(
                    get: { profile.id == model.currentProfileId },
                    set: { _ in
                        Task { await model.connect(to: profile) }
                    }
                ))
                if profile.id == model.currentProfileId {
                    item.keyboardShortcut("k", modifiers: [.command])
                } else {
                    item
                }
            }

            Divider()

            Button("New connection...") {
                model.presentManageConnections(mode: .new)
            }
            Button("Manage connections...") {
                model.presentManageConnections(mode: .manage)
            }
        }
    }

    // MARK: View menu (M6)

    /// The View items live in SwiftUI's automatic View menu (a second
    /// `CommandMenu("View")` would show up as a duplicate menu title).
    private var viewMenu: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Select all") {
                model.selectAllVisible()
            }
            .keyboardShortcut("a", modifiers: [.command])
            .disabled(!model.phase.isConnected)

            Button("Setup columns...") {
                model.showColumnsSetup = true
            }

            Divider()

            groupingToggle("Folder grouping", \.folders)
            groupingToggle("Label grouping", \.labels)
            groupingToggle("Tracker grouping", \.trackers)

            Divider()

            Toggle("Filter pane", isOn: Binding(
                get: { model.showFilterSidebar },
                set: { model.setShowFilterPane($0) }
            ))
            .keyboardShortcut(Key.f11, modifiers: [])

            Toggle("Info pane", isOn: Binding(
                get: { model.showDetailsPane },
                set: { model.setShowInfoPane($0) }
            ))
            .keyboardShortcut(Key.f12, modifiers: [])

            Toggle("Status bar", isOn: Binding(
                get: { model.showStatusBar },
                set: { model.setShowStatusBar($0) }
            ))

            Divider()

            Button("Search") {
                model.focusSearch()
            }
            .keyboardShortcut("s", modifiers: [.option])

            ForEach(Array(FilterID.allCases.enumerated()), id: \.element) { index, id in
                Button(id.title) {
                    model.filter = .status(id)
                }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(index + 1)")),
                    modifiers: [.option]
                )
            }

            Divider()

            detailsTabButton("General", tab: .general, key: "g")
            detailsTabButton("Trackers", tab: .trackers, key: "k")
            detailsTabButton("Peers", tab: .peers, key: "p")
            detailsTabButton("Files", tab: .files, key: "f")
        }
    }

    private func groupingToggle(
        _ title: String,
        _ keyPath: WritableKeyPath<GroupingToggles, Bool>
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.groupings[keyPath: keyPath] },
            set: { model.groupings[keyPath: keyPath] = $0 }
        ))
    }

    /// Alt+G/K/P/F: jump the details pane to a tab.
    private func detailsTabButton(
        _ title: String,
        tab: DetailsTab,
        key: Character
    ) -> some View {
        Button(title) {
            model.selectedDetailsTab = tab
        }
        .keyboardShortcut(KeyEquivalent(key), modifiers: [.option])
    }

    // MARK: Tools menu (M6)

    private var toolsMenu: some Commands {
        CommandMenu("Tools") {
            Button("Transmission options...") {
                Task { await model.presentTransmissionOptions() }
            }
            .keyboardShortcut(Key.f9, modifiers: [])
            .disabled(!model.phase.isConnected)

            Button("Application options...") {
                model.showApplicationOptions = true
            }
            .keyboardShortcut(Key.f9, modifiers: [.control])

            Button("Update blocklist") {
                Task { await model.updateBlocklist() }
            }
            .disabled(!model.phase.isConnected)

            Divider()

            Toggle("Use alternate bandwidth settings", isOn: Binding(
                get: { model.session?.altSpeedEnabled ?? false },
                set: { newValue in
                    if newValue != (model.session?.altSpeedEnabled ?? false) {
                        Task { await model.toggleAltSpeedEnabled() }
                    }
                }
            ))
            .keyboardShortcut(Key.f8, modifiers: [])
            .disabled(model.session == nil)
        }
    }
}
