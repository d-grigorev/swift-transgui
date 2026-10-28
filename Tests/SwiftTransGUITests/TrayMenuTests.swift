import Testing
@testable import SwiftTransGUI

/// The tray menu's first item is a toggle: its title follows the main
/// window's visibility. The suite runs on the main actor because it reads
/// the shared visibility state.
@Suite @MainActor
struct TrayMenuTests {
    @Test("Visible window offers the hide action")
    func visible() {
        #expect(TrayMenuTitle.title(isWindowVisible: true) == "Minimize to tray")
    }

    @Test("Hidden window offers the restore action")
    func hidden() {
        #expect(TrayMenuTitle.title(isWindowVisible: false) == "Open SwiftTransGUI")
    }

    @Test("Fresh state starts visible")
    func initialVisibility() {
        #expect(MainWindowVisibility.shared.isVisible)
    }

    @Test("Close behavior follows the Disable tray option")
    func closeBehavior() {
        // Tray enabled: close is intercepted → hide to tray, app survives.
        #expect(CloseBehavior.shouldInterceptClose(disableTray: false))
        #expect(!CloseBehavior.shouldTerminateAfterLastWindowClosed(disableTray: false))

        // Tray disabled: close goes through → the app exits on close.
        #expect(!CloseBehavior.shouldInterceptClose(disableTray: true))
        #expect(CloseBehavior.shouldTerminateAfterLastWindowClosed(disableTray: true))
    }
}
