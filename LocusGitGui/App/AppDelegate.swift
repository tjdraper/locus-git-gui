import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updates = UpdateController()
    /// Started before anything needs Git, since shell startup files can take seconds to run.
    private let loginShellEnvironment = Task { await LoginShellEnvironment.capture() }
    private lazy var gitChoice = GitChoiceStore(loginShell: loginShellEnvironment)
    private lazy var firstRunWindow = FirstRunWindowPresenter(gitChoice: gitChoice)
    private let gitMissingNotice = GitMissingNotice()
    private var hasAskedForRepository = false
    private lazy var repositoryWindows = RepositoryWindowCoordinator(
        gitChoice: gitChoice,
        checkForMissingGit: { [weak self] in self?.checkForMissingGit() }
    )
    private lazy var repositoryOpening = RepositoryOpeningWorkflow(
        gitChoice: gitChoice,
        windows: repositoryWindows,
        showChecklist: { [weak self] in self?.firstRunWindow.show() },
        checkForMissingGit: { [weak self] in self?.checkForMissingGit() }
    )

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

        gitChoice.onGitChosen = { [weak self] in
            self?.repositoryOpening.openFoldersWaitingForGit()
        }
        // An install from before the checklist existed has never chosen a Git either.
        if isFirstRun || GitChoice().executableURL == nil {
            firstRunWindow.show()
        }
    }

    /// Catches a Git uninstalled or moved while the app was in the background.
    func applicationDidBecomeActive(_: Notification) {
        checkForMissingGit()
    }

    /// Folders dropped on the Dock icon or on the app in Finder, and `open -a` from Terminal.
    func application(_: NSApplication, open urls: [URL]) {
        repositoryOpening.open(urls)
    }

    /// Asked at launch when the app wasn't opened with folders, and when the Dock icon is clicked
    /// with no windows open.
    func applicationShouldOpenUntitledFile(_: NSApplication) -> Bool {
        true
    }

    /// There is nothing untitled to make, so this asks for a repository instead, but only when
    /// there is a Git to open one with. At launch the checklist or the missing-Git alert already
    /// covers the alternative; later, the checklist does.
    func applicationOpenUntitledFile(_: NSApplication) -> Bool {
        let isLaunching = !hasAskedForRepository
        hasAskedForRepository = true
        Task {
            guard case .available = await gitChoice.checkAvailability() else {
                if !isLaunching {
                    firstRunWindow.show()
                }
                return
            }
            if !firstRunWindow.isVisible {
                repositoryOpening.showOpenPanel()
            }
        }
        return true
    }

    /// Reached through the responder chain from the main menu's About item.
    @objc func showAboutPanel(_: Any?) {
        AboutPanel.show()
    }

    /// Reached through the responder chain from File > Open.
    @objc func openRepository(_: Any?) {
        repositoryOpening.showOpenPanel()
    }

    /// Reached through the responder chain from the Help menu.
    @objc func showSetupChecklist(_: Any?) {
        firstRunWindow.show()
    }

    private func checkForMissingGit() {
        Task {
            let availability = await gitChoice.checkAvailability()
            gitMissingNotice.update(for: availability, checklistIsVisible: firstRunWindow.isVisible) {
                firstRunWindow.show()
            }
        }
    }
}
