import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updates = UpdateController()
    private let emptyWindow = EmptyWindowPresenter()
    /// Started before anything needs Git, since shell startup files can take seconds to run.
    private let loginShellEnvironment = Task { await LoginShellEnvironment.capture() }
    private lazy var gitChoice = GitChoiceStore(loginShell: loginShellEnvironment)
    private lazy var firstRunWindow = FirstRunWindowPresenter(gitChoice: gitChoice)
    private let gitMissingNotice = GitMissingNotice()

    func applicationDidFinishLaunching(_: Notification) {
        MainMenu.install(appName: "Locus Git Gui", checkForUpdatesItem: updates.makeMenuItem())
        // Settled before Sparkle starts, which marks every install as launched before.
        let isFirstRun = FirstRunStatus().settleAtLaunch() == .pending
        // Before the updater starts, since accepting the move relaunches from the new location.
        // On a first run the setup checklist makes the offer instead.
        if !isFirstRun {
            ApplicationsFolderMoveWorkflow().offerIfNeeded()
        }
        // Answered before Sparkle's first check, which would otherwise still look for betas.
        BetaTrackExitWorkflow().offerIfNeeded()
        updates.start()
        emptyWindow.show()

        if isFirstRun {
            firstRunWindow.show()
        }
        Task {
            // An install from before the checklist existed has never chosen a Git either.
            if await gitChoice.checkAvailability() == .notChosen {
                firstRunWindow.show()
            }
        }
    }

    /// Catches a Git uninstalled or moved while the app was in the background.
    func applicationDidBecomeActive(_: Notification) {
        Task {
            let availability = await gitChoice.checkAvailability()
            gitMissingNotice.update(for: availability, checklistIsVisible: firstRunWindow.isVisible) {
                firstRunWindow.show()
            }
        }
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

    /// Reached through the responder chain from the Help menu.
    @objc func showSetupChecklist(_: Any?) {
        firstRunWindow.show()
    }
}
