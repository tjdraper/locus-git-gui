import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updates = UpdateController()
    private let emptyWindow = EmptyWindowPresenter()

    func applicationDidFinishLaunching(_: Notification) {
        MainMenu.install(appName: "Locus Git Gui", checkForUpdatesItem: updates.makeMenuItem())
        // Before the updater starts, since accepting the move relaunches from the new location.
        ApplicationsFolderMoveWorkflow().offerIfNeeded()
        // Answered before Sparkle's first check, which would otherwise still look for betas.
        BetaTrackExitWorkflow().offerIfNeeded()
        updates.start()
        emptyWindow.show()
    }

    /// Clicking the Dock icon, or opening the app again from Finder while it runs, is a request
    /// to see the window, whether it is minimized, buried behind other apps or closed.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        emptyWindow.show()
        return false
    }

    /// Reached through the responder chain from the main menu's About item.
    @objc func showAboutPanel(_: Any?) {
        AboutPanel.show()
    }
}
