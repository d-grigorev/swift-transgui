# SwiftTransGUI — agent working notes

SwiftUI macOS rewrite of Transmission Remote GUI's **UI/UX only** (reference
project: https://github.com/transmission-remote-gui/transgui — Lazarus/Pascal;
do NOT copy its code/architecture; UI strings, layout and workflow may be
mirrored). Target: any Transmission daemon via `/transmission/rpc` — developed
and tested against **Transmission 3.00, RPC 16**. No server address, username
or password ships with the project.

## Build & verify

```bash
swift build                          # debug build (must always pass)
swift test                           # unit tests: Tests/TransGUICoreTests + Tests/SwiftTransGUITests
./Scripts/make-app.sh                # release build → build/SwiftTransGUI.app
swift run rpc-selftest '<password>' --host <host[:port]>   # headless live RPC check
open build/SwiftTransGUI.app         # launch GUI for manual check
```

CI (`.github/workflows/ci.yml`) runs `swift build` (debug + release),
`swift test` and `./Scripts/make-app.sh` on a macOS 26+ runner — it never
contacts any server (no secrets in CI).

The app ships with **no server address** (`RpcEndpoint.default.host` is empty;
Connect opens the connections dialog and the first configured address
persists in UserDefaults). The password is never stored in the repo — the app
prompts for it and saves it in the Keychain (service
`ru.dgreenday.swifttransgui.rpc`). `rpc-selftest` likewise requires
`--host host[:port]` and usually `--user <name>` (plus optional `--path`,
`--ssl`).

## Architecture

- **TransGUICore** (library target) — no SwiftUI imports:
  - `RpcTypes.swift` — `RpcEndpoint` (empty host/username by default), `RpcError`.
  - `TransmissionClient.swift` — actor; POST JSON-RPC, Basic auth, 409
    `X-Transmission-Session-Id` handshake with retries, `result == "success"`
    envelope decoding, `getTorrents(fields:ids:)` helper that unwraps
    `arguments.torrents`, `getTorrentDetails(fields:ids:)` for a single row.
  - `Models.swift` — `Torrent`, `TrackerStat`, `Peer`, `TorrentFile`,
    `SessionInfo` (hyphenated CodingKeys — RPC keys are kebab-case!),
    `SessionStats`, `FreeSpace`, `TorrentListFields` (list field set),
    `DetailsFields` (per-tab details field sets incl. throttled `pieces`),
    `TorrentSetArgs` (`torrent-set` file wanted/priority args **plus** the
    M4 scalar/tracker keys: `bandwidthPriority`, `labels`,
    `downloadLimited`/`downloadLimit`/`uploadLimited`/`uploadLimit`,
    `seedRatioMode`/`seedRatioLimit`/`seedIdleMode`/`seedIdleLimit`,
    `trackerAdd`/`trackerRemove`/`trackerReplace` — all optional so unused
    keys are omitted), `TrackerReplacePairs` (flat `[id, url, ...]`),
    `TorrentActionArgs` (`ids` optional → omitted = all torrents),
    `TorrentSetLocationArgs`, `SessionAltSpeedArgs` (`alt-speed-enabled`),
    `SessionSetArgs` (M6 `session-set` payload: every Transmission options
    key + the global speed limits, all optional so only the changed keys
    hit the wire), `BlocklistUpdateResponse` (`blocklist-size`),
    `PropertiesFields` (properties-dialog fetch set),
    add-flow args/responses: `TorrentAddArgs` (`paused`/`filename`/`metainfo`/
    `download-dir`/`peer-limit`), `TorrentAddResponse` (`torrent-added` or
    `torrent-duplicate` → `AddedTorrent{id,name,hashString}`), `TorrentRemoveArgs`,
    `TorrentRenamePathArgs`, `TorrentIdsArgs`, `TrackerAddArgs` (`trackerAdd`,
    camelCase!), `AddTorrentFields`.
    `torrent-get` responses always wrap rows in `{arguments: {torrents: [...]}}`.
  - `Bencode.swift` — minimal bencode (BEP 3) decoder + `infoHash(ofMetainfo:)`
    (SHA-1 of the raw `info` dict bytes via CryptoKit `Insecure.SHA1`, no
    re-encoding). `TorrentMeta.swift` — `TorrentMeta.parse` (name, flattened
    `announce-list`, infohash) and `MagnetLink` (infohash incl. base32,
    `tr=` trackers, bare-hash → magnet conversion).
  - `Formatting.swift` — `Fmt` (sizes `1.2 GB`, speeds `1.5 MB/s` / blank when 0,
    ETA `3dh, 20m`, ratio `%.3f` / `∞`, relative dates `3d, 5h`).
  - `TorrentState.swift` — status mapping (0 stopped … 6 seeding; stopped +
    complete = `Finished`), `effectiveError` (global + tracker errors),
    progress/ETA/seed/peer derivations, `FilterID` (All/Downloading/Completed/
    Active/Inactive/Stopped/Error/Waiting + counts), `FilterSelection`
    (status | folder | label | tracker), `Groupings` (folder/label/tracker
    groups; tracker host = scheme/port/`bt.`-prefix stripped).
  - `Keychain.swift`.
- **SwiftTransGUI** (executable):
  - `App/AppModel.swift` — `@MainActor @Observable` single model: `phase`
    (idle/connecting/connected/failed), `session`, `torrents`, `freeSpace`,
    `filter`, `searchText`, `selection`, polling (5 s; session refresh every
    5th tick), `visibleTorrents`, `sorted(_:by:)`, details pane
    (`selectedDetailsTab`, `details: DetailsData?`, per-tab fetch guarded by
    a generation counter; `pieces` fetched only every 4th General refresh),
    file actions `setFileWanted` / `setFilePriority` (`torrent-set`),
    add-flow state (`addTorrentSheet`, `addTorrentQueue`, `addTorrentBusy`,
    `duplicateTorrentAlert`, `showAddLinkSheet`, `addTorrentError`),
    M4 dialog state (`propertiesSheet`, `dataLocationSheet`, `labelsSheet`,
    `renameSheet`, `removeConfirm`, `verifyConfirm` — cleared on disconnect).
  - `App/AppModel+Actions.swift` — M4 actions: `canAct` + RPC-version gates
    (`canForceStart` ≥14, `canRemoveData` ≥4, `canSetLabels` ≥16,
    `canSetLocation` ≥6, `canRename` ≥15), start/forceStart/startAll/
    stop/stopAll/reannounce/verify/`queueMove` (all via `torrent-*` action
    methods + immediate refresh), `setBandwidthPriority`, `setLabels`,
    `renameTorrent`, `setDataLocation`, `copyMagnetLinks` (NSPasteboard),
    `toggleAltSpeedEnabled` (`session-set` + session refresh), confirmations
    (`askRemove`/`askVerify` → 3-option/2-option alerts), sheet
    presentation/application, and `TrackerDiff.compute` (reference tracker
    diff: drop unchanged lines, pair leftovers as `trackerReplace`, extras
    as `trackerAdd`/`trackerRemove`).
  - `App/AppModel+AddTorrent.swift` — the M5 flow: pick/queue jobs → paused
    `torrent-add` → sheet or duplicate alert → apply (remove+re-add on
    destination change, `torrent-set` wanted/unwanted + peer-limit,
    `torrent-rename-path`, `torrent-start`), `selectTorrent` (flips filter/
    search off if they'd hide the row), `AddTorrentDefaults` (UserDefaults:
    destination history most-recent-first, per-folder templates,
    `StartTorrentOnAdd`, last peer limit), `AddTorrentNaming.sanitized`
    (`* ? | < > " ~` → `_`). Application options' "Prompt for download
    options…" switch skips the sheet (`finishDirectAdd`).
  - `App/ConnectionProfiles.swift` — M6 connections manager: `ConnectionProfile`
    (Codable/Sendable: name, host, port, useSSL, rpcPath, username,
    alwaysReconnect, isDefault; the built-in profile for
    `RpcEndpoint.default` is always present and never deletable),
    `ConnectionProfileStore` (UserDefaults `connections` +
    `LastConnectionProfile`), `ManageConnectionsMode`, and the AppModel
    profile actions (`connect(to:)` — disconnect/switch/reconnect with a
    password prompt per profile Keychain account — and `updateProfiles`).
  - `App/AppSettings.swift` — UserDefaults-backed Application options:
    `RefreshInterval` (drives polling, 1…999 s, default 5), minimized
    interval, average-speeds, add-torrent prompt/delete/clipboard flags,
    `SpeedMenuDown`/`SpeedMenuUp` presets (default
    `100, 500, 1000, 2000, 5000`), view-pane toggles.
  - `App/AppModel+Settings.swift` — `TransmissionOptionsDraft` (typed copy of
    the daemon settings + `sessionSetArgs()` diff that sends **only** the
    changed keys), options-sheet presentation, `setGlobalSpeedLimit`,
    `updateBlocklist`, `testIncomingPort`.
  - `App/Notifications.swift` — `DownloadNotifier` (UNUserNotificationCenter,
    every entry point guarded by `Bundle.main.bundleIdentifier != nil` so
    `swift run` degrades silently).
  - `App/SwiftTransGUIApp.swift` — scene + `CommandMenu("Torrent")` (M4
    full menu: Add ⌘O / Add link ⇧⌘O, Start F3 / Force start ⇧F3 / Start
    all ⌃F3 / Stop F4 / Stop all ⌃F4 / Remove ⌦ / Remove+data ⇧⌦,
    Priority ▸, Queue ▸ (⌃⇧1/⌃1/⌃2/⌃⇧2), Reannounce ⌃R, Verify,
    Set data location F6, Set labels F7, Rename F2, Properties ⌥↩,
    **Connect submenu** (profiles with a checkmark on the current one +
    New connection… / Manage connections…, ⌘K on the current profile),
    Disconnect ⇧⌘D) + M6 `CommandGroup(after: .sidebar)` **View** menu
    (Select all ⌘A, Setup columns…, groupings, Filter pane F11 / Info pane
    F12 / Status bar toggles, Search ⌥S, filters ⌥1…8, details tabs
    ⌥G/K/P/F) + `CommandMenu("Tools")` (Transmission options… F9,
    Application options… ⌃F9, Update blocklist, Use alternate bandwidth
    settings F8) + `Key` enum (F-key `KeyEquivalent`s, U+F705…U+F70F;
    always pass `modifiers:` — the default is `.command`).
  - `Views/MainWindow.swift` — VSplitView { HSplitView (sidebar | table);
    DetailsPaneView } + status bar, sheets (password, add-torrent, add-link),
    duplicate/error alerts, `.dropDestination(for: URL.self)` for .torrent drops.
  - `Views/Details/DetailsPaneView.swift` — TabView tabs General/Trackers/
    Peers/Files (`Files (N)`)/Statistics, shared placeholder state, plus the
    Statistics grid; sibling files `GeneralDetailsView.swift` (piece bar +
    Transfer/Torrent grids), `TrackerPeerViews.swift`, `FilesDetailsView.swift`
    (folder tree, checkboxes + priority menu → `torrent-set`).
  - `Views/Details/FileTreeSupport.swift` — shared tree builder (`FileTree.rows`,
    `FileTreeRow`, `FileContext`) used by both the Files tab and the add
    sheet, plus `FileTemplate` (case-insensitive `*`/`?` glob over basenames).
  - `Views/Dialogs/AddTorrentSheet.swift` (caption `Add new torrent`):
    destination combo + history menu + Browse (local NSOpenPanel, pragmatic)
    + trash (`Delete destination folder`), Template field (help `for example:
    *.avi *.mkv tom*jerry*.avi`, applies live, remembered per folder),
    Save as (sanitized; disabled for magnets), Peer limit stepper 1…999,
    `Torrent contents` GroupBox (live `Free disk space:` debounced
    `free-space`, File name/Size table with folder checkboxes, Select all/
    none, `Size: <selected> / <total>`), `Start torrent` checkbox (persisted
    `StartTorrentOnAdd`, checkbox + OK render bold when unchecked).
    Esc dismissal has an `onDisappear` safety net that removes the paused
    torrent so the queue can't stall.
  - `Views/Dialogs/AddLinkSheet.swift` (caption `Add torrent link`): field +
    inline `No link was specified.`; bare 40-hex hash → magnet link.
  - `Views/TorrentTableView.swift` — Table (12 columns in **two**
    `@TableColumnBuilder` groups — builder caps at 10), `KeyPathComparator`
    sort order (macOS 26 Table API: `Table(_, selection:, sortOrder:,
    columnCustomization:)`, column closures take the **row only**),
    per-column `.customizationID()` / `.defaultVisibility()` via the shared
    `TorrentColumn` enum (Queue position hidden by default), persisted
    through `AppModel.saveColumnCustomization()`,
    `NameCell`, `ProgressCell`,
    M4 `.contextMenu(forSelectionType: Int.self, menu:primaryAction:)`
    (menu acts on clicked ∪ selected; `primaryAction` = double-click →
    Properties). Menu helpers are `@MainActor`.
  - `Views/FilterSidebarView.swift`, `MainToolbar.swift` (connect **Menu**
    = profile list with a checkmark on the current one + New/Manage
    connections…; Add torrent... button = `plus`, help `Add torrent`; M4
    Start/Stop/Remove + Queue up/down + checkable turtle toggle (`Key.f8`)
    with `Divider()`s between groups; `SearchField` gained `@FocusState`
    driven by `AppModel.focusSearchTick`), `StatusBarView.swift` (M6:
    right-click on the `D:`/`U:` panels → `Unlimited` + the Application
    options presets, `session-set` through `setGlobalSpeedLimit`),
    `PasswordPromptView.swift`.
  - `Views/Dialogs/` — M4 sheets (all wired from MainWindow via
    `.sheet(item:)` on the AppModel state): `TorrentPropertiesSheet`
    (General/Advanced tabs, NSViewRepresentable `TriStateCheckbox` for the
    AllowGrayed seed-ratio/idle checkboxes, TextEditor tracker list),
    `SetDataLocationSheet` (history combo + Browse + move checkbox),
    `SetLabelsSheet` (comma-separated), `RenameSheet` (validates
    `* ? | < > " ~` → `Invalid name specified.`).
    M6 sheets: `ManageConnectionsSheet` (caption
    `Manage connections to Transmission` / `New connection to Transmission`,
    name combo + New/Rename/Delete with the
    `Are you sure to delete connection '<name>'?` confirmation, `Transmission`
    tab: help text, Remote host (`No host name specified.`), Port 1…65535 +
    Use SSL, Authentication required + Always auto-reconnect, User name /
    Password (`••••••••` placeholder; the Keychain entry is only overwritten
    when a new password is typed), RPC path),
    `TransmissionOptionsSheet` (Download / Network (WAN) / Bandwidth /
    Queue tabs, `Test port` → `port-test`, validation messages from the
    reference), `ApplicationOptionsSheet` (General / Misc tabs),
    `ColumnsSetupSheet` (caption `Columns setup - Torrents`, checklist,
    `At least single column must be visible.`).

## Gotchas discovered (don't re-learn these)

- `@Observable` (Observation), **not** `ObservableObject` — views use
  `@Environment(AppModel.self)` + `@Bindable`.
- RPC JSON keys are kebab-case (`download-dir`, `rpc-version`) → CodingKeys.
- `session-get` with no arguments returns everything; decode a subset.
- Plain HTTP is allowed only because `Info.plist` sets
  `NSAppTransportSecurity → NSAllowsArbitraryLoads`.
- Table sort: `sortOrder` is `[KeyPathComparator<Torrent>]`;
  `rows.sorted(using:)` works with plain Swift struct keypaths (verified).
- Foundation `SortDescriptor` also works for non-UI sorting.
- `Fmt.speed(_:)` returns `String?` (nil = blank cell).
- `pieces` (piece map) is a **base64 string** at RPC 16 — one bit per piece;
  `torrent-set` replies with `arguments: {}` (decode `EmptyArguments`).
- `torrent-add` replies with `arguments: {"torrent-added": {...}}` or
  `{"torrent-duplicate": {...}}` (keys `id`/`name`/`hashString`); very old
  daemons answer `result: "duplicate torrent"` instead → `RpcError.server`.
- RPC 16 `torrent-set` has **no** `download-dir` → to honor a changed
  destination, remove (no local data) + re-add paused (reference does this too).
- The tracker-merge RPC key is camelCase `trackerAdd` (not kebab-case).
- Swift `KeyEquivalent` has no `.insert` (SDK checked) → add shortcuts are
  ⌘O / ⇧⌘O instead of the reference's Insert / Ctrl+Insert.
- `SHA-1` for infohash comes from CryptoKit `Insecure.SHA1` (no new deps);
  hash the raw `info` dict byte range — never re-encode bencode.
- Duplicate-alert bindings: clear `duplicateTorrentAlert` synchronously in the
  button action before the async task, otherwise the alert's dismiss-binding
  (set false right after the action) races the `Task` and can stall the queue.
- Queue-move methods are **`queue-move-top|up|down|bottom`** — NOT
  `torrent-queue-move-*` (the daemon answers `method name not recognized`;
  verified live against 3.00).
- `torrent-verify` on a running torrent: a `torrent-stop` sent while the
  recheck is in flight can be swallowed — the daemon resumes the torrent
  when the check completes. Wait until `status ∉ {1,2}` before stopping,
  and re-send the stop if the status stays running.
- `View.keyboardShortcut(_:)` defaults to **`.command`** modifiers — bare
  F-keys / Delete must pass `modifiers: []` explicitly.
- SwiftPM: an executable target with `@main` breaks once the target has
  more than one source file while a file is named `main.swift`
  ("'main' attribute cannot be used in a module that contains top-level
  code") → rpc-selftest's file is `RpcSelfTest.swift`, not `main.swift`.
- SwiftUI `Toggle` has no mixed state → tri-state (checked/greyed/unchecked)
  checkboxes need a small `NSViewRepresentable` NSButton (`.switch` +
  `.mixed`), cycling on → mixed → off on click.
- `trackerReplace` wire format on RPC ≤ 17 is a **flat array**
  `[id, url, id, url, ...]` (each element encoded separately — a tuple
  array can't synthesize this, hence `TrackerReplacePairs`); seed
  ratio/idle modes: 0 = follow global (grey), 1 = override (checked),
  2 = unlimited (unchecked).
- `contextMenu(forSelectionType:menu:primaryAction:)` on a Table:
  `primaryAction` fires on double-click; the menu closure is nonisolated,
  so view helpers touching `@MainActor` model state are marked `@MainActor`.
- **The dev server's disk was full** (`free-space` = 0 b): every freshly
  added torrent carried `Unable to save torrent file: No space left on
  device`, and stock 3.00's `tr_torrentSetAnnounceList` then silently
  skips announce-list changes while still answering `success` — so
  tracker edits (properties > Advanced, duplicate-merge) were a no-op.
  The wire keys themselves are fine (proven: a malformed `trackerAdd`
  element is rejected with `invalid argument`). **M6 update: the disk was
  freed** (`free-space` = 7 TB, `blocklist-update` answers, the actions
  test now runs the full tracker add/replace/remove sequence).
- **Two AppModel methods must not share a base name**: `start()`
  (launch/auto-connect) shadowed the M4 torrent action `start(ids:)` —
  Swift prefers the overload needing no default arguments, so the
  toolbar/menu "Start" buttons silently called the *launch* method (which
  toggles a connected session off). Renamed to `launch()` in M6.
- **`CommandMenu("View")` produces a second "View" menu**: SwiftUI already
  creates an (empty) one. Add the items to *that* menu with
  `CommandGroup(after: .sidebar) { … }` (confirmed by dumping
  `NSApp.mainMenu` from a throwaway QA build).
- **`TableColumnCustomization` has no ordering API** — only
  `subscript(visibility:)` and `resetOrder()`; its Codable payload is an
  undocumented alternating `[key, value]` array, so the reference's Up/Down
  column buttons are omitted (native header drag-reorder still works).
  `.automatic` means "use the column's `defaultVisibility`".
- **`alt-speed-time-day` bits**: Transmission's `tr_sched_day` (3.00
  `transmission.h`) is Sunday = 1<<0 … Saturday = 1<<6 — the reference's
  checkbox row reads Mo…Sa, Su with bits 1…6 then 0.
- **Ad-hoc-signed .app vs Keychain**: an item created by `swift run` is not
  readable by the ad-hoc-signed bundle (different code requirement), and
  `Keychain.load` runs synchronously on the main actor — macOS then pops a
  keychain dialog that **stalls the whole app** until answered. With no
  item at all the lookup returns nil instantly. `security
  delete-generic-password` can delete an item another app created without
  prompting (the data ACL does not gate deletion), but reading it with
  `security … -w` prompts and blocks.
- Headless UI checks: `CGWindowListCopyWindowInfo` lists sheet windows and
  their sizes, `NSApp.mainMenu` dumps the menu bar (titles, key
  equivalents, checkmarks); full-screen `screencapture` is useless while
  the display is idle/locked.

## UI/UX spec (from reference app)

Main window: toolbar (connect, actions, search) · left filter pane (status
filters with `(count)`, then Folders/Labels/Trackers groups) · torrent table
(Name/Size/Done-progress-bar/Status/Seeds/Peers/Down/Up/ETA/Ratio/Queue/Labels)
· bottom details pane tabs: **General, Trackers, Peers, Files, Statistics**
· status bar: `Transmission 3.00 at host:port`, `D: x/s (limit/s)`,
`U: x/s (limit/s)`, `Free: size`.

Details > General: top strip `Downloaded:` + piece bar + `100.0%`; sections
**Transfer** (Status, Error, Remaining, Downloaded, Uploaded, Wasted,
Download speed, Upload speed, Share ratio, Down limit, Up limit, Seeds, Peers,
Max peers, Tracker, Tracker update on, Last active) and **Torrent** (Name,
Created on, Total size, Pieces, Hash, Comment, Added on, Completed on,
Magnet Link, Labels).
Trackers: columns Name, Status, Update in, Seeds.
Peers: columns Host, Port(hidden), Client, Flags, Have, Up speed, Down speed
(no Country column — reference app loads GeoIP db; skip).
Files: tree (File name, Size, Done, %, Priority), folder rows, checkboxes =
wanted/unwanted, priority skip/low/normal/high (`torrent-set` with
`files-wanted`/`files-unwanted`/`priority-*`, priorities -1000/-1/0/1).
Statistics: `Global statistics:` table (Downloaded, Uploaded, Files added,
Active time × Current/Cumulative) from `session-stats`.

## Milestones

- [x] M1 scaffold + RPC + live connect + list + filters + status bar
- [ ] M2 search/filters polish (largely done inside M1)
- [x] M3 details pane (5 tabs)
- [x] M4 torrent actions (menus, context menus, toolbar, shortcuts)
- [x] M5 add-torrent flows (file/link/drag-drop + file selection)
- [x] M6 options dialogs, connections manager, columns setup, notifications

## M5 verification (headless)

`swift run rpc-selftest '<password>' --add-test '<path to .torrent>'` reads the
file (bencode parse prints name/infohash/trackers), adds it **paused** via
metainfo, verifies it appears (`torrent-get` by id), removes it without
delete-local-data, and asserts the torrent count returns to the initial value.
If the torrent already exists it prints `torrent-duplicate id=…` and leaves
the list untouched (duplicate path). GUI: `./Scripts/make-app.sh && open
build/SwiftTransGUI.app`; drag `.torrent` files onto the window to test drops.

## M4 verification (headless)

`swift run rpc-selftest '<password>' --actions-test` adds one transient
torrent from **synthesized bencode** (name `transgui-actions-test`, no file on
disk; leftovers of aborted runs are cleaned with delete-local-data first),
then exercises: start -> status leaves 0, `torrent-verify` -> observes
`status=2`, waits for the recheck, stop -> status 0, `queue-move`
top/bottom/up/down (asserts `queuePosition` changes when the torrent shares
its queue), `bandwidthPriority` 1->0 read back, labels set + read back,
`torrent-rename-path` + read back, `torrent-reannounce`, `torrent-set`
speed limits 100/50 KB/s -> read back -> cleared, the properties-dialog keys
(`peer-limit`, `seedRatioMode/Limit`, `seedIdleMode/Limit`), and
`torrent-set-location` (move=false to `<download-dir>/actions-test-loc`,
then back), and the tracker keys (`trackerAdd`/`trackerReplace` flat
pairs/`trackerRemove` — full add/replace/remove sequence when the daemon
can persist torrent files; otherwise empty-list probes expect
`invalid argument` for each key and the edits are skipped with a NOTE,
because the dev server's disk is full). Finally it removes the torrent
**with** `delete-local-data` and asserts the torrent count and every
pre-existing torrent field (name/status/labels/queue/priority/location)
are unchanged. GUI: exercise
the toolbar/menu/context-menu/shortcut entry points manually; double-click
opens Torrent properties.

## M6 verification (headless)

`swift run rpc-selftest '<password>' --session-test` re-reads the session,
changes **one** harmless key (`speed-limit-down` → 123), reads it back,
then restores the original value unconditionally (even after a failure)
and asserts the restore — observed 5060 → 123 → 5060 on two runs, plus an
independent `session-get` diff (`speed-limit-down` = 5060, the
`speed-limit-down-enabled` flag untouched). `port-test` is read-only;
`blocklist-update` now succeeds on the freed disk. The GUI surface was
checked with throwaway QA code (deleted before the commit): an
`NSApp.mainMenu` dump proves the View / Tools / Torrent / Connect menus
and every new key equivalent (⌥1…8, ⌥S, ⌥G/K/P/F, F9 / ⌃F9, F8, F11,
F12, ⌘K), and `CGWindowListCopyWindowInfo` shows the new sheets opening
at their expected sizes (Columns setup 320×320, Application options
560×364, Manage connections 560×411, New connection 560×403,
Transmission options 640×396). Download-complete notifications only run
inside the signed .app bundle (`Bundle.main.bundleIdentifier` guard), so
they still need a manual check with a torrent that finishes while the app
is open; the status-bar speed-limit menus were exercised by code review
only (they need a right-click on the live status bar).
