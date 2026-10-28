import AppKit
import SwiftUI

/// Turns the window's close paths — red close button, ⌘W, File > Close —
/// into a hide: `windowShouldClose` orders the window out and vetoes the
/// close, so the app keeps running behind its menu-bar tray icon (see
/// `TraySupport.swift`).
///
/// Added as a `.background(...)` of the `WindowGroup` root view. SwiftUI
/// may install its own `NSWindowDelegate`: ours chains to it (every
/// callback it doesn't implement itself is forwarded to the previous
/// delegate) and is re-installed whenever the representable updates or the
/// window becomes key.
struct WindowCloseInterceptor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> InterceptorView {
        let view = InterceptorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: InterceptorView, context: Context) {
        context.coordinator.attach(to: view)
    }

    /// Invisible background view whose only job is to report window
    /// (re)attachment — `updateNSView` can run before the view has one.
    final class InterceptorView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // AppKit calls this on the main thread; the coordinator's work
            // is main-actor isolated (NSView itself is not annotated).
            MainActor.assumeIsolated {
                coordinator?.attach(to: self)
            }
        }
    }

    /// Installed as the window's delegate (the delegate reference is
    /// `weak`, hence the window-anchored strong reference) and vetoes the
    /// close.
    final class Coordinator: NSObject, NSWindowDelegate {
        /// The window this coordinator is installed on.
        private weak var window: NSWindow?
        /// The delegate installed before ours (SwiftUI's); every callback
        /// we don't implement ourselves is forwarded to it, so fullscreen,
        /// zoom and friends keep whatever behavior SwiftUI gave them.
        private weak var previousDelegate: (any NSWindowDelegate)?

        /// `objc_setAssociatedObject` key: a stable address, never
        /// dereferenced.
        nonisolated(unsafe) private static var windowAnchorKey: UInt8 = 0

        /// (Re)installs the close interception for `view`'s window. Called
        /// on every SwiftUI update and (via `didBecomeKey`) whenever
        /// SwiftUI may have re-taken the delegate.
        @MainActor
        func attach(to view: NSView) {
            guard let window = view.window else { return }
            if self.window !== window {
                self.window = window
                MainWindowRegistry.window = window
                // `NSWindow.delegate` is weak: keep this coordinator alive
                // exactly as long as its window lives.
                objc_setAssociatedObject(
                    window,
                    &Coordinator.windowAnchorKey,
                    self,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidBecomeKey(_:)),
                    name: NSWindow.didBecomeKeyNotification,
                    object: window
                )
                // Native minimize/deminiaturize flips the tray menu's
                // visibility state like the explicit hide/show paths.
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidMiniaturize(_:)),
                    name: NSWindow.didMiniaturizeNotification,
                    object: window
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidDeminiaturize(_:)),
                    name: NSWindow.didDeminiaturizeNotification,
                    object: window
                )
            }
            installDelegate(on: window)
        }

        /// Takes the delegate over, remembering whoever held it before so
        /// their callbacks keep working through forwarding.
        @MainActor
        private func installDelegate(on window: NSWindow) {
            guard window.delegate !== self else { return }
            if let current = window.delegate, current !== previousDelegate {
                previousDelegate = current
            }
            window.delegate = self
        }

        /// SwiftUI can reinstall its own delegate at any time; re-assert
        /// ours as soon as the window becomes key again. Doubles as the
        /// `NSWindowDelegate` callback of the same name (the signature
        /// matches), while the notification observer still fires even when
        /// someone else holds the delegate.
        @MainActor
        @objc func windowDidBecomeKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            installDelegate(on: window)
        }

        /// The window was minimized to the dock: not on screen, so the tray
        /// menu offers to open it.
        @MainActor
        @objc func windowDidMiniaturize(_ notification: Notification) {
            MainWindowVisibility.shared.isVisible = false
        }

        /// Back on screen from a dock minimize: the tray menu flips back.
        @MainActor
        @objc func windowDidDeminiaturize(_ notification: Notification) {
            MainWindowVisibility.shared.isVisible = true
        }

        // MARK: NSWindowDelegate

        /// Close button, ⌘W and File > Close: with the tray enabled, hide
        /// the window instead of closing it (deferred one run-loop turn so
        /// AppKit finishes the close query first). With "Disable tray"
        /// checked the close goes through for real and the app exits via
        /// the delegate's terminate-after-last-window policy.
        @MainActor
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard CloseBehavior.shouldInterceptClose(
                disableTray: AppSettings.disableTray) else {
                return true
            }
            DispatchQueue.main.async {
                hideMainWindow()
            }
            return false
        }

        /// No window-level undo manager — the plain AppKit default when no
        /// delegate provides one.
        @MainActor
        func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
            nil
        }

        // MARK: Forwarding to the previous delegate

        /// Covers optional `NSWindowDelegate` callbacks we don't
        /// implement: report them as supported when the chained delegate
        /// supports them…
        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector)
                || previousDelegate?.responds(to: aSelector) == true
        }

        /// …and hand them over. `forwardingTarget` is only consulted for
        /// selectors this class does not implement, so our own callbacks
        /// always win.
        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            guard !super.responds(to: aSelector),
                  let previous = previousDelegate,
                  previous.responds(to: aSelector) else {
                return nil
            }
            return previous
        }
    }
}
