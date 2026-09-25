import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updates = UpdateController()
    /// Started before anything needs Git, since shell startup files can take seconds to run.
    private let loginShellEnvironment = Task { await LoginShellEnvironment.capture() }
    private lazy var gitChoice = GitChoiceStore(loginShell: loginShellEnvironment)
    /// Finishing the checklist leads to the dashboard, which it kept from showing at launch.
    private lazy var firstRunWindow: FirstRunWindowPresenter = FirstRunWindowPresenter(gitChoice: gitChoice) { [weak self] in
        guard let self, !repositoryWindows.hasOpenWindows else { return }
        dashboard.show()
    }
    private let gitMissingNotice = GitMissingNotice()
    private var hasAskedForRepository = false
    private let logs = GitCommandLogs()
    private let recents = RecentRepositoryStore()
    private lazy var repositoryWindows: RepositoryWindowCoordinator = RepositoryWindowCoordinator(
        gitChoice: gitChoice,
        logs: logs,
        recents: recents,
        checkForMissingGit: { [weak self] in self?.checkForMissingGit() },
        lastWindowClosed: { [weak self] in self?.showDashboardWhenGitWorks(isLaunching: false) }
    )
    private lazy var repositoryOpening: RepositoryOpeningWorkflow = RepositoryOpeningWorkflow(
        gitChoice: gitChoice,
        windows: repositoryWindows,
        recents: recents,
        didOpenRepository: { [weak self] in self?.dashboard.close() },
        showChecklist: { [weak self] in self?.firstRunWindow.show() },
        checkForMissingGit: { [weak self] in self?.checkForMissingGit() }
    )
    private lazy var recentOpener: RecentRepositoryOpener = RecentRepositoryOpener(recents: recents, opening: repositoryOpening)
    private lazy var recentMenus: RecentRepositoryMenus = RecentRepositoryMenus(recents: recents) { [weak self] repository in
        self?.recentOpener.open([repository])
    }
    private lazy var dashboard: DashboardWindowPresenter = DashboardWindowPresenter(
        recents: recents,
        checker: RecentRepositoryChecker(
            gitChoice: gitChoice,
            logs: logs,
            checkForMissingGit: { [weak self] in self?.checkForMissingGit() }
        ),
        opener: recentOpener,
        displayNames: DisplayNameWorkflow(
            recents: recents,
            gitChoice: gitChoice,
            logs: logs,
            checkForMissingGit: { [weak self] in self?.checkForMissingGit() }
        ),
        showOpenPanel: { [weak self] in self?.repositoryOpening.showOpenPanel() }
    )

    func applicationDidFinishLaunching(_: Notification) {
        MainMenu.install(
            appName: "Locus Git Gui",
            checkForUpdatesItem: updates.makeMenuItem(),
            openRecentItem: recentMenus.openRecentItem,
            dashboardFileItems: dashboard.fileMenuItems,
            dashboardViewItems: dashboard.viewMenuItems
        )
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

    /// There is nothing untitled to make, so this shows the dashboard instead.
    func applicationOpenUntitledFile(_: NSApplication) -> Bool {
        let isLaunching = !hasAskedForRepository
        hasAskedForRepository = true
        showDashboardWhenGitWorks(isLaunching: isLaunching)
        return true
    }

    /// Only when there is a Git to open a repository with. At launch the checklist or the missing-Git
    /// alert already covers the alternative; later, the checklist does.
    private func showDashboardWhenGitWorks(isLaunching: Bool) {
        Task {
            guard case .available = await gitChoice.checkAvailability() else {
                if !isLaunching {
                    firstRunWindow.show()
                }
                return
            }
            if !firstRunWindow.isVisible {
                dashboard.show()
            }
        }
    }

    /// Repository windows' state holds only folder paths, which decode as strings.
    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        recentMenus.dockMenu()
    }

    /// Reached through the responder chain from the main menu's About item.
    @objc func showAboutPanel(_: Any?) {
        AboutPanel.show()
    }

    /// Reached through the responder chain from File > Open.
    @objc func openRepository(_: Any?) {
        repositoryOpening.showOpenPanel()
    }

    /// Reached through the responder chain from File > Show Dashboard, whatever window is in front.
    @objc func showDashboard(_: Any?) {
        dashboard.show()
    }

    /// Reached through the responder chain from File > New Tab and the tab bar's add button. The
    /// repository chosen joins the tabs of the window in front.
    @objc func newWindowForTab(_: Any?) {
        dashboard.showForNewTab(joining: NSApp.keyWindow.flatMap { repositoryWindows.isRepositoryWindow($0) ? $0 : nil })
    }

    /// Called by `RepositoryWindowRestoration`, which macOS creates itself and so can't be handed
    /// the windows it restores into.
    func restoreWindow(for repository: Repository, completionHandler: @escaping (NSWindow?, (any Error)?) -> Void) {
        repositoryWindows.restore(repository, completionHandler: completionHandler)
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
