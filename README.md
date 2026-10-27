# SwiftTransGUI

A native macOS SwiftUI client for remotely controlling a Transmission daemon
via its JSON-RPC protocol. The UI/UX is modeled on
[Transmission Remote GUI](https://github.com/transmission-remote-gui/transgui)
(uTorrent-like layout: filter sidebar, torrent table, details pane, status bar),
implemented with original Swift/SwiftUI architecture.

## Requirements

- macOS 26+
- Xcode 26 / Swift 6 toolchain

## Build & run

```bash
./Scripts/make-app.sh          # release build → build/SwiftTransGUI.app
open build/SwiftTransGUI.app
```

Development build and tests:

```bash
swift build                     # debug build
swift test                      # unit tests (offline, no server needed)
swift run SwiftTransGUI         # (prefer the .app bundle: plain HTTP needs Info.plist ATS)
```

Headless RPC check against a server (no default address is built in — pass
`--host`, matching the app's empty-by-default server configuration):

```bash
swift run rpc-selftest '<rpc-password>' --host <host[:port]> [--user <name>] [--path <rpc path>] [--ssl]
swift run rpc-selftest '<rpc-password>' --host <host[:port]> --add-test '<path/to/file.torrent>'  # add/verify/remove cycle
```

The server address is configured in the app on first launch (Connect opens
the connections dialog; profiles persist in UserDefaults) and the RPC
password is entered once in the password prompt and stored in the macOS
Keychain (service `ru.dgreenday.swifttransgui.rpc`). Neither the address nor
the password is stored in the repository.

## Features

- Connect to a Transmission daemon (host/port/RPC path/basic auth), password
  in Keychain, automatic reconnect on refresh failures
- Torrent list with sortable columns (Name, Size, Done progress bar, Status,
  Seeds, Peers, speeds, ETA, Ratio, Queue position, Labels) and search filter
- Filter sidebar: All / Downloading / Completed / Active / Inactive /
  Stopped / Error / Waiting with live counts, plus Folder / Label / Tracker
  groupings
- Details pane: General (transfer info + piece map), Trackers, Peers,
  Files (tree with checkboxes and priorities), Statistics
- Add torrents from .torrent files (drag & drop) or magnet/URL links with
  destination history, file selection template and per-file priorities
- Status bar: connection state, total speeds with limits, free disk space

## Project layout

- `Sources/TransGUICore` — RPC client, models, formatting, filters (no UI)
- `Sources/SwiftTransGUI` — SwiftUI app (views, app model)
- `Sources/rpc-selftest` — headless connectivity/flow tests
- `Tests/TransGUICoreTests`, `Tests/SwiftTransGUITests` — unit tests (Swift Testing)
- `.github/workflows/ci.yml` — CI: build (debug+release), `swift test`, bundle assembly on macOS 26+ runners

## License & credits

Licensed under the **GNU General Public License, version 2 or later** — the
same license as the reference project. See [`LICENSE`](LICENSE) for the full
text and [`NOTICE`](NOTICE) for attribution.

- The UI/UX is modeled on
  [Transmission Remote GUI](https://github.com/transmission-remote-gui/transgui)
  (Copyright (c) 2008-2019 Yury Sidorov and the Transmission Remote GUI
  working group, GPLv2+). No code from that project was reused — only its
  UI strings, layout and workflow, reimplemented with an original
  Swift/SwiftUI architecture.
- This implementation was **rewritten entirely by the AI model
  MiMo-V2.6-Flash** (`mimo-v2.6-flash`) without human programming input.
