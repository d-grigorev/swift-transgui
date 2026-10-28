import AppKit
import SwiftUI

// MARK: - Hide / show

/// Hides the app's ordinary windows (normal level, not a sheet) so the app
/// keeps running behind its menu-bar tray icon. Menu-bar, sheet and palette
/// windows are deliberately left alone.
@MainActor
func hideMainWindow() {
    for window in NSApp.windows
    where window.isVisible
        && window.level == .normal
        && window.sheetParent == nil {
        window.orderOut(nil)
    }
    MainWindowVisibility.shared.isVisible = false
}

/// Brings the main window back: de-miniaturizes it, orders it front, and
/// brings the app to the foreground — the restore path for the tray
/// menu's "Open SwiftTransGUI" and the dock icon's reopen callback.
///
/// Plain `NSApp.activate()` is *cooperative*: measured to be denied while
/// another app holds activation (QA run: still `active=false` 3 s after
/// show). The restore therefore forces activation with
/// `.activateIgnoringOtherApps` and re-asserts key focus as the (async)
/// activation lands.
@MainActor
func showMainWindow() {
    guard let window = mainTrayWindow() else { return }
    NSApp.setActivationPolicy(.regular)
    forceActivate()
    if window.isMiniaturized {
        window.deminiaturize(nil)
    }
    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(nil)
    forceActivate()
    reassertKeyFocus(window, attempt: 0)
    MainWindowVisibility.shared.isVisible = true
}

/// Requests activation. `.activateIgnoringOtherApps` is deprecated *and a
/// no-op since macOS 14*, so this is the cooperative `activate()` plus
/// `activateAllWindows` — with `reassertKeyFocus` retrying while the
/// (async, system-permissioned) activation lands.
@MainActor
private func forceActivate() {
    NSApp.activate()
    _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
}

/// Activation lands asynchronously: re-check key focus for up to ~1.5 s
/// after the restore and pull the window forward if it did not take it.
@MainActor
private func reassertKeyFocus(_ window: NSWindow, attempt: Int) {
    guard attempt < 10, window.isVisible else { return }
    if window.isKeyWindow, NSRunningApplication.current.isActive {
        return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        guard window.isVisible else { return }
        if !window.isKeyWindow {
            forceActivate()
            window.makeKey()
        }
        if attempt + 1 < 10 {
            reassertKeyFocus(window, attempt: attempt + 1)
        }
    }
}

/// The window hosting the `WindowGroup` content — registered by
/// `WindowCloseInterceptor` when it installs itself — falling back to the
/// first titled normal-level window (sheets excluded).
@MainActor
private func mainTrayWindow() -> NSWindow? {
    if let registered = MainWindowRegistry.window {
        return registered
    }
    return NSApp.windows.first {
        $0.level == .normal
            && $0.styleMask.contains(.titled)
            && $0.sheetParent == nil
    }
}

/// The main window as known by `WindowCloseInterceptor`. `NSWindow` is not
/// `Sendable`, so the static is main-actor isolated (every caller here
/// runs on the main actor anyway).
@MainActor
enum MainWindowRegistry {
    /// Weak — SwiftUI owns the window and can release it at any time.
    static weak var window: NSWindow?
}

/// Observable source of truth for the main window's visibility: every hide
/// and show path (tray menu, close interception, dock reopen, native
/// minimize) updates it, and the tray menu's item title flips on it.
@MainActor
@Observable
final class MainWindowVisibility {
    static let shared = MainWindowVisibility()
    private init() {}

    /// Starts visible — the window group opens on launch.
    var isVisible = true
}

// MARK: Tray menu titles

/// The tray menu's first item is a toggle whose title follows the window.
enum TrayMenuTitle {
    static func title(isWindowVisible visible: Bool) -> String {
        visible ? "Minimize to tray" : "Open SwiftTransGUI"
    }
}

// MARK: Close behavior

/// What closing the window does — driven by the "Disable tray" option
/// (Application options → Tray icon). One source of truth, consulted by
/// the close interceptor and the app delegate's terminate policy.
enum CloseBehavior {
    /// Tray enabled: swallow the close and hide to the tray instead.
    static func shouldInterceptClose(disableTray: Bool) -> Bool {
        !disableTray
    }

    /// Tray disabled: closing the last window quits the app.
    static func shouldTerminateAfterLastWindowClosed(disableTray: Bool) -> Bool {
        disableTray
    }
}

// MARK: Tray status item

/// The menu-bar tray icon, built manually as an `NSStatusItem` instead of
/// a SwiftUI `MenuBarExtra`. Measured root cause of the mispositioned
/// popup: with `MenuBarExtra(.menu)` the status button carries no menu or
/// action of its own — SwiftUI pops the `NSMenu` at coordinates it derives
/// itself from the button's frame, and that frame went stale or shifted
/// during display reconfiguration (measured: menu35 pt below the menu
/// bar while the desktop was mid-scale-change, and the popup following a
/// garbage button frame to the screen corner — i.e. never anchored under
/// the icon actually drawn in the menu bar). `NSStatusItem.menu` is
/// positioned by AppKit against the button itself at pop time, which is
/// the platform-guaranteed anchor.
@MainActor
final class TrayStatusController: NSObject, NSMenuDelegate {
    static let shared = TrayStatusController()
    private override init() {}

    private var statusItem: NSStatusItem?

    /// Creates the status item and its menu. Idempotent; called from
    /// `AppDelegate.applicationDidFinishLaunching`.
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(
            systemSymbolName: "arrow.down.circle",
            accessibilityDescription: "SwiftTransGUI"
        )
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Removes the status item (the "Disable tray" option). Idempotent.
    func uninstall() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    /// Applies the tray-enabled state at launch and when the option
    /// changes — no restart required.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            install()
        } else {
            uninstall()
        }
    }

    // MARK: NSMenuDelegate

    /// Rebuilt on every open so the toggle title follows the window's
    /// visibility (`TrayMenuTitle` + `MainWindowVisibility` unchanged).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let visible = MainWindowVisibility.shared.isVisible
        let toggle = NSMenuItem(
            title: TrayMenuTitle.title(isWindowVisible: visible),
            action: #selector(toggleWindowVisibility),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func toggleWindowVisibility() {
        if MainWindowVisibility.shared.isVisible {
            hideMainWindow()
        } else {
            showMainWindow()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: App delegate

/// App-level policy for the tray behavior: hiding the last window must not
/// quit the app, and a dock-icon click while every window is hidden brings
/// the main window back (the only restore path — the tray menu itself
/// carries no "Show" item).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Installs the tray status item unless the "Disable tray" option is
    /// on (SwiftUI.AppDelegate forwards this to the adaptor delegate,
    /// verified by the QA harness).
    func applicationDidFinishLaunching(_ notification: Notification) {
        TrayStatusController.shared.setEnabled(!AppSettings.disableTray)
    }

    /// Belt & braces: with the tray enabled, hiding the last window must
    /// not quit the app; with "Disable tray" the app exits on close.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        CloseBehavior.shouldTerminateAfterLastWindowClosed(
            disableTray: AppSettings.disableTray)
    }

    /// Dock-icon click: with no visible windows (all hidden to the tray),
    /// re-key the main window; otherwise let AppKit do its usual thing.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        if !hasVisibleWindows {
            showMainWindow()
        }
        return true
    }
}

