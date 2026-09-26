import AppKit
import os
import SwiftUI

/// The window for one repository.
final class RepositoryWindowController: NSWindowController, NSWindowDelegate {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "RepositoryWindow")

    let repository: Repository
    var onDisplayNameRead: ((String?) -> Void)?
    private let commands: RepositoryCommandRunner
    private let viewStates: RepositoryViewStateStore
    private let sidebar: SidebarModel
    private let sidebarView: NSView
    private let pinning: SidebarPinWorkflow
    private let commitColumns: CommitColumnsCoordinator
    private let diffOptions: DiffOptionsStore
    private lazy var openedWindows = OpenedWindowsCoordinator(
        commands: commands,
        diffOptions: diffOptions,
        session: commitColumns.workingAreaSession,
        repositoryName: name,
        repositoryWindow: self
    )
    private lazy var commitGraph = CommitGraphWriter(repository: repository, run: commands.run)
    private let columns: RepositorySplitViewController
    private let failureSheet = GitFailureSheetPresenter()
    private let titleItem: RepositoryTitleItem
    private lazy var toolbar = RepositoryToolbar(
        title: titleItem,
        activity: ActivityIndicator(log: commands.log) { [weak self] in self?.openedWindows.showActivity() }
    ) { [weak self] in self?.showBackgroundFailure() }
    private lazy var scheduler = RefreshScheduler { [weak self] reason in await self?.refresh(because: reason) }
    private lazy var watcher = RepositoryFileWatcher(repository: repository) { [weak self] in
        self?.scheduler.requestSoon(because: .filesChanged)
    }
    /// The latest failure of something the app did by itself, shown as the toolbar warning until a
    /// later attempt succeeds.
    private var backgroundFailure: GitFailure?
    /// The frame outside full screen, which is the one worth coming back to.
    private var windowFrame: String?
    /// As the tab shows it, which the coordinator works out with the other open repositories'.
    private(set) var name: String
    private lazy var focusCycle = ColumnFocusCycle(
        sidebar: sidebar,
        sidebarView: sidebarView,
        isSidebarShown: { [weak self] in self?.columns.isSidebarCollapsed == false },
        history: commitColumns.history,
        detail: commitColumns.detailColumn
    )

    init(commands: RepositoryCommandRunner, displayName: String?, viewStates: RepositoryViewStateStore) {
        self.commands = commands
        self.viewStates = viewStates
        repository = commands.repository
        titleItem = RepositoryTitleItem(repository: repository, displayName: displayName)
        name = displayName ?? repository.workTree.lastPathComponent
        let viewState = viewStates.state(for: repository)
        windowFrame = viewState.windowFrame
        sidebar = SidebarModel(state: viewState)
        pinning = SidebarPinWorkflow(sidebar: sidebar, workTree: repository.workTree)
        diffOptions = DiffOptionsStore(options: viewState.diffOptions)
        let sidebarController = NSHostingController(rootView: SidebarView(model: sidebar))
        // The split view sets the columns' sizes, not SwiftUI.
        sidebarController.sizingOptions = []
        sidebarView = sidebarController.view
        commitColumns = CommitColumnsCoordinator(commands: commands, diffOptions: diffOptions, commitDraft: viewState.commitDraft)
        columns = RepositorySplitViewController(
            sidebar: sidebarController,
            history: commitColumns.history,
            detail: commitColumns.detailColumn,
            columns: viewState.columns
        )
        let window = RepositoryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            // The sidebar runs the full height of the window, under the toolbar.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Still read by the Window menu, Mission Control and VoiceOver while the toolbar shows it.
        window.title = (repository.workTree.path as NSString).abbreviatingWithTildeInPath
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // Kept apart from the dashboard and Activity windows, which also count as documents to
        // macOS's automatic tabbing.
        window.tabbingIdentifier = "RepositoryWindow"
        window.identifier = RepositoryWindowRestoration.identifier
        window.restorationClass = RepositoryWindowRestoration.self
        super.init(window: window)
        // Setting the content resizes the window to it, so the size is set again after.
        window.contentViewController = columns
        window.setContentSize(NSSize(width: 1200, height: 760))
        connectSidebar()
        columns.onColumnsChange = { [weak self] in self?.saveViewState() }
        diffOptions.onChange = { [weak self] _ in self?.saveViewState() }
        connectCommitColumns()
        window.onCommandClick = { [titleItem] event in titleItem.showPathMenu(for: event) }
        window.onTab = { [weak self, weak window] backward in
            self?.focusCycle.move(from: window?.firstResponder, backward: backward) ?? false
        }
        toolbar.attach(to: window)
        window.delegate = self
        watcher.start()
        scheduler.requestNow(because: .windowOpened)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// Commands for the history or the commit reach them from whichever column has focus, and
    /// pinning reaches the sidebar from anywhere in the window.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if SidebarPinWorkflow.actions.contains(action) {
            return pinning
        }
        return commitColumns.target(forAction: action) ?? super.supplementalTarget(forAction: action, sender: sender)
    }

    /// Shows the sidebar first if it's hidden.
    private func revealInSidebar(_ id: SidebarItemID) {
        columns.showSidebar()
        sidebar.reveal(id)
    }

    /// As last read from the repository's `.locus` folder.
    var displayName: String? {
        titleItem.title.displayName
    }

    /// The tab has its own title, since the window's full path is cut off before the part that tells
    /// repositories apart. The windows opened from this one name the repository the same way.
    func showName(_ name: String) {
        if name != self.name {
            self.name = name
            openedWindows.showRepositoryName(name)
        }
        guard let tab = window?.tab, tab.title != name else { return }
        tab.title = name
        tab.toolTip = (repository.workTree.path as NSString).abbreviatingWithTildeInPath
    }

    /// Where the window was when this repository's was last closed, if that's still on a screen.
    /// True when the window was put there. A window restored after a relaunch doesn't need this,
    /// since macOS brings back its frame itself.
    func moveToRememberedFrame() -> Bool {
        guard let window, let windowFrame else { return false }
        window.setFrame(from: windowFrame)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            return true
        }
        window.setContentSize(NSSize(width: 1200, height: 760))
        return false
    }

    func windowDidMove(_: Notification) {
        rememberFrame()
    }

    func windowDidResize(_: Notification) {
        rememberFrame()
    }

    func window(_: NSWindow, willEncodeRestorableState state: NSCoder) {
        RepositoryWindowRestoration.encode(repository, into: state)
    }

    /// Covers changes FSEvents can't see, such as a `git config` edit outside the repository.
    func windowDidBecomeKey(_: Notification) {
        scheduler.requestNow(because: .windowBecameKey)
    }

    func windowWillClose(_: Notification) {
        saveViewState()
        watcher.stop()
        scheduler.cancel()
        openedWindows.closeAll()
    }

    private func refresh(because reason: RefreshScheduler.Reason) async {
        let started = ContinuousClock.now
        do {
            let snapshot = try await RepositorySnapshot.read(repository, running: commands.run)
            show(RepositoryTitleBar(status: snapshot.status, operation: snapshot.operation))
            commitColumns.show(snapshot)
            openedWindows.show(snapshot) { commitColumns.workingArea.files(in: Set(WorkingAreaGroup.allCases)) }
            // Read only once Git has reached the repository, so a folder that's gone or out of
            // reach isn't taken for one whose name was cleared.
            let displayName = await Self.readDisplayName(in: repository.workTree)
            if displayName != self.displayName {
                titleItem.setDisplayName(displayName)
                onDisplayNameRead?(displayName)
            }
            let refs = try await Ref.readList(running: commands.run)
            sidebar.show(try await SidebarContents.read(refs: refs, running: commands.run), pins: await Self.pins(in: repository.workTree))
            commitColumns.show(refs: refs, head: snapshot.status.branch, selection: sidebar.selection, contents: sidebar.contents)
            openedWindows.showLabels(commitColumns.labels)
            // Once Git has reached the repository, so a folder that's gone isn't written to.
            commitGraph.writeIfMissing()
            clearBackgroundFailure()
            let elapsed = ContinuousClock.now - started
            let files = snapshot.status.files.count
            Self.log.info("Refreshed \(files) files in \(elapsed, privacy: .public) (\(reason.rawValue, privacy: .public))")
        } catch is CancellationError {
            return
        } catch is RepositoryCommandRunner.NoUsableGit {
            return
        } catch let failure as GitReadFailure {
            if failure.command == RepositoryStatus.command {
                show(.unavailable)
            }
            reportBackgroundFailure(GitFailure(
                summary: failure.outputWasUnreadable
                    ? "Locus Git Gui couldn’t read Git’s report on this repository’s \(failure.subject)."
                    : "Git couldn’t read this repository’s \(failure.subject).",
                arguments: failure.command.arguments,
                result: failure.result
            ))
        } catch let ChildProcess.Failure.couldNotStart(error) {
            // Git never ran, so there is no output of its own. The system's reason stands in for it.
            show(.unavailable)
            reportBackgroundFailure(GitFailure(
                summary: "Git couldn’t start in this repository’s folder.",
                arguments: RepositoryStatus.command.arguments,
                result: ChildProcess.Result(status: -1, standardOutput: Data(), standardError: Data(error.localizedDescription.utf8))
            ))
        } catch {
            Self.log.error("Refresh failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Off the main actor, since reading the folder can wait on macOS asking for permission.
    @concurrent
    private static func readDisplayName(in workTree: URL) async -> String? {
        RepositoryDisplayName.read(from: workTree).name
    }

    /// Read after Git's reads, so a pin changed meanwhile is less likely to be put back for a moment.
    @concurrent
    private static func pins(in workTree: URL) async -> SidebarPins {
        SidebarPins.read(from: workTree)
    }

    private func rememberFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        windowFrame = window.frameDescriptor
        saveViewState()
    }

    private func saveViewState() {
        var state = RepositoryViewState()
        state.windowFrame = windowFrame
        state.selection = sidebar.selection
        state.collapsedSections = sidebar.collapsedSections
        state.collapsedRemotes = sidebar.collapsedRemotes
        state.columns = columns.columns
        state.diffOptions = diffOptions.options
        state.commitDraft = commitColumns.workingArea.draft
        viewStates.set(state, for: repository)
    }

    private func show(_ titleBar: RepositoryTitleBar) {
        guard let window else { return }
        window.subtitle = titleBar.subtitle
        titleItem.title.subtitle = titleBar.subtitle
        window.isDocumentEdited = titleBar.isEdited
    }

    private func reportBackgroundFailure(_ failure: GitFailure) {
        backgroundFailure = failure
        toolbar.showWarning(failure.summary)
        Self.log.error("Background refresh failed with status \(failure.result.status, privacy: .public)")
    }

    private func clearBackgroundFailure() {
        guard backgroundFailure != nil else { return }
        backgroundFailure = nil
        toolbar.hideWarning()
    }

    private func showBackgroundFailure() {
        guard let backgroundFailure else { return }
        present(backgroundFailure) { [weak self] in
            self?.scheduler.requestNow(because: .retried)
        }
    }

}

/// How the columns and the windows opened from them reach the window.
extension RepositoryWindowController {
    fileprivate func connectSidebar() {
        pinning.window = window
        sidebar.onChange = { [weak self] in
            guard let self else { return }
            saveViewState()
            commitColumns.show(selection: sidebar.selection, contents: sidebar.contents)
        }
    }

    fileprivate func connectCommitColumns() {
        commitColumns.reveal = { [weak self] id in self?.revealInSidebar(id) }
        commitColumns.present = { [weak self] failure, retry in self?.present(failure, retry: retry) }
        commitColumns.open = { [weak self] commit in self?.openedWindows.openCommit(commit, from: self?.window) }
        commitColumns.openFileWindow = { [weak self] request in self?.openedWindows.openFile(request, from: self?.window) }
        let session = commitColumns.workingAreaSession
        session.queue.didRun = { [weak self] in self?.scheduler.requestNow(because: .commandRan) }
        session.queue.presentFailure = { [weak self] failure in self?.presentCommandFailure(failure) }
        session.editor.onDraftChange = { [weak self] _ in self?.saveViewState() }
        commitColumns.openWorkingArea = { [weak self] in self?.openWorkingAreaWindow() }
        // Revealing a label from a commit's window brings this window forward to show it.
        openedWindows.reveal = { [weak self] id in
            self?.showWindow(nil)
            self?.revealInSidebar(id)
        }
        openedWindows.showFailure = { [weak self] failure, window, retry in
            guard let self else { return }
            failureSheet.present(failure, repository: repository, on: window, wasOpenedByUser: true, retry: retry)
        }
    }
}

/// Failures shown as a sheet on the window.
extension RepositoryWindowController {
    /// A command the user ran, such as a commit, that failed, on the window it was run from. They
    /// acknowledge it with OK.
    fileprivate func presentCommandFailure(_ failure: GitFailure) {
        let windows = [openedWindows.workingAreaWindow, window].compactMap(\.self)
        guard let target = windows.first(where: \.isKeyWindow) ?? window else { return }
        failureSheet.present(failure, repository: repository, on: target, wasOpenedByUser: false, retry: nil)
    }

    fileprivate func openWorkingAreaWindow() {
        openedWindows.openWorkingArea(from: window)
    }

    /// Opened by the user from a warning or a column's Show Details, so it has a Try Again.
    fileprivate func present(_ failure: GitFailure, retry: @escaping () -> Void) {
        guard let window else { return }
        failureSheet.present(failure, repository: repository, on: window, wasOpenedByUser: true, retry: retry)
    }
}

/// View menu commands, which reach the window through the responder chain from anywhere in it.
extension RepositoryWindowController {
    /// Reached through the responder chain from View > Show Activity.
    @objc func showActivity(_: Any?) {
        openedWindows.showActivity()
    }
    /// Reached through the responder chain from View > Filter Sidebar.
    @objc func filterSidebar(_: Any?) {
        columns.showSidebar()
        sidebar.requestFilterFocus()
    }
    /// Reached through the responder chain from View > Go to Uncommitted Changes, from anywhere in
    /// the window. From another branch's history it goes back to the checked-out branch's, where the
    /// working area is. The subject takes focus, since writing the message is usually what's next.
    @objc func goToUncommittedChanges(_: Any?) {
        if commitColumns.history.workingArea == nil {
            sidebar.selection = nil
        }
        guard commitColumns.history.workingArea != nil else {
            NSSound.beep()
            return
        }
        commitColumns.history.selectWorkingArea()
        commitColumns.workingArea.focusSubject()
    }

    /// Reached through the responder chain from View > Open Uncommitted Changes in New Window, and
    /// passed on by the windows opened from this one, so it opens whatever the history shows.
    @objc func openUncommittedChangesWindow(_: Any?) {
        openWorkingAreaWindow()
    }

    /// Commands the commit, file and working area windows pass on to the repository's window.
    static let repositoryActions: Set<Selector> = [#selector(openUncommittedChangesWindow(_:)), #selector(showActivity(_:))]
}

extension RepositoryWindowController: CommandPaletteDestinationSource {
    var paletteDestinations: [CommandPaletteDestination] {
        guard let contents = sidebar.contents else { return [] }
        return SidebarPaletteDestinations.make(from: contents) { [weak self] id in self?.revealInSidebar(id) }
    }

    func paletteChoices(for command: AppCommand) -> [CommandPaletteDestination]? {
        let kinds: Set<CommandPaletteDestination.Kind>
        switch command {
        case .goToBranch: kinds = [.branch, .remoteBranch]
        case .goToTag: kinds = [.tag]
        case .goToStash: kinds = [.stash]
        case .goToParentCommit: return commitColumns.history.parentChoices
        case .revealCommitInSidebar: return commitColumns.history.labelChoices
        default: return nil
        }
        return paletteDestinations.filter { kinds.contains($0.kind) }
    }
}
