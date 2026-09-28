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
    let sidebar: SidebarModel
    private let sidebarView: NSView
    private let pinning: SidebarPinWorkflow
    private lazy var historyWindowCommand = HistoryWindowCommand(sidebar: sidebar) { [weak self] item in
        self?.openedWindows.openHistory(of: item, from: self?.window)
    }
    let commitColumns: CommitColumnsCoordinator
    private let diffOptions: DiffOptionsStore
    let messageFormat: MessageFormatStore
    private let diffPlaces: DiffPlaceStore
    private(set) lazy var openedWindows = OpenedWindowsCoordinator(
        commands: commands,
        diffOptions: diffOptions,
        diffPlaces: diffPlaces,
        session: commitColumns.workingAreaSession,
        repositoryName: name,
        repositoryWindow: self
    )
    private lazy var commitGraph = CommitGraphWriter(repository: repository, run: commands.run)
    let remotes: RemotesCoordinator
    let operations: RepositoryOperationsCoordinator
    let columns: RepositorySplitViewController
    private let failureSheet = GitFailureSheetPresenter()
    private lazy var warning: BackgroundFailureWarning =
        BackgroundFailureWarning(repository: repository, sheet: failureSheet, toolbar: toolbar)
    private let titleItem: RepositoryTitleItem
    private lazy var toolbar: RepositoryToolbar = RepositoryToolbar(
        title: titleItem,
        fetchOptions: remotes.makeFetchOptionsMenu(),
        activity: ActivityIndicator(log: commands.log) { [weak self] in self?.openedWindows.showActivity() }
    ) { [weak self] in self?.warning.showDetails(on: self?.window) }
    private lazy var scheduler = RefreshScheduler { [weak self] reason in await self?.refresh(because: reason) }
    private lazy var watcher = RepositoryFileWatcher(repository: repository) { [weak self] in
        self?.scheduler.requestSoon(because: .filesChanged)
    }
    /// As of the last refresh, whose ahead and behind counts the next can reuse.
    private var lastRefs: [Ref]?
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

    init(
        commands: RepositoryCommandRunner,
        displayName: String?,
        viewStates: RepositoryViewStateStore,
        askpass: AskpassServer,
        fetchPreferences: FetchPreferences
    ) {
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
        messageFormat = MessageFormatStore(showsMarkdown: viewState.showsMessageAsMarkdown)
        diffPlaces = DiffPlaceStore(memory: viewState.diffPlaces)
        let sidebarController = NSHostingController(rootView: SidebarView(model: sidebar))
        // The split view sets the columns' sizes, not SwiftUI.
        sidebarController.sizingOptions = []
        sidebarView = sidebarController.view
        commitColumns = CommitColumnsCoordinator(
            commands: commands,
            diffOptions: diffOptions,
            diffPlaces: diffPlaces,
            viewState: viewState
        )
        let queue = commitColumns.workingAreaSession.queue
        remotes = RemotesCoordinator(commands: commands, queue: queue, askpass: askpass, preferences: fetchPreferences)
        operations = RepositoryOperationsCoordinator(commands: commands, session: commitColumns.workingAreaSession)
        columns = RepositorySplitViewController(
            sidebar: sidebarController,
            history: HistoryColumnController(history: commitColumns.history, bar: HistoryBars.make(remotes.progress, operations.status)),
            detail: commitColumns.detailColumn,
            columns: viewState.columns
        )
        let window = RepositoryWindow(showing: repository)
        super.init(window: window)
        window.show(columns)
        connectSidebar()
        columns.onColumnsChange = { [weak self] in self?.saveViewState() }
        diffOptions.onChange = { [weak self] _ in self?.saveViewState() }
        diffPlaces.onChange = { [weak self] _ in self?.saveViewState() }
        connectCommitColumns(restoring: viewState.openWindows)
        connectRemotes()
        connectOperations()
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
        if HistoryWindowCommand.actions.contains(action) {
            return historyWindowCommand
        }
        if let target = remotes.target(forAction: action) {
            return target
        }
        if let target = operations.target(forAction: action) ?? messageFormat.target(forAction: action) {
            return target
        }
        return commitColumns.target(forAction: action) ?? super.supplementalTarget(forAction: action, sender: sender)
    }

    /// Shows the sidebar first if it's hidden.
    func revealInSidebar(_ id: SidebarItemID) {
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
        window.setContentSize(RepositoryWindow.contentSize)
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
        remotes.stop()
        openedWindows.closeAll()
    }

    private func refresh(because reason: RefreshScheduler.Reason) async {
        let started = ContinuousClock.now
        do {
            let snapshot = try await RepositorySnapshot.read(repository, running: commands.run)
            show(RepositoryTitleBar(status: snapshot.status, operation: snapshot.operation))
            commitColumns.show(snapshot)
            let workingAreaFiles = { self.commitColumns.workingArea.files(in: Set(WorkingAreaGroup.allCases)) }
            openedWindows.show(snapshot, workingAreaFiles: workingAreaFiles)
            openedWindows.restoreIfNeeded(from: window, workingAreaFiles: workingAreaFiles)
            // Read only once Git has reached the repository, so a folder that's gone or out of
            // reach isn't taken for one whose name was cleared.
            let displayName = await Self.readDisplayName(in: repository.workTree)
            if displayName != self.displayName {
                titleItem.setDisplayName(displayName)
                onDisplayNameRead?(displayName)
            }
            let refs = if let lastRefs {
                try await Ref.readList(reusingCountsFrom: lastRefs, running: commands.run)
            } else {
                try await Ref.readList(running: commands.run)
            }
            lastRefs = refs
            sidebar.show(try await SidebarContents.read(refs: refs, running: commands.run), pins: await Self.pins(in: repository.workTree))
            commitColumns.show(refs: refs, head: snapshot.status.branch, selection: sidebar.selection, contents: sidebar.contents)
            if let contents = sidebar.contents {
                openedWindows.show(refs: refs, head: snapshot.status.branch.commit, contents: contents, labels: commitColumns.labels)
                remotes.show(branch: snapshot.status.branch, contents: contents)
            }
            operations.show(snapshot, refs: refs, contents: sidebar.contents)
            toolbar.showTracking(ahead: snapshot.status.branch.ahead ?? 0, behind: snapshot.status.branch.behind ?? 0)
            // Once Git has reached the repository, so a folder that's gone isn't written to.
            commitGraph.writeIfMissing()
            warning.clear(.refresh)
            let elapsed = ContinuousClock.now - started
            let files = snapshot.status.files.count
            Self.log.info("Refreshed \(files) files in \(elapsed, privacy: .public) (\(reason.rawValue, privacy: .public))")
        } catch {
            guard let refreshFailure = RefreshFailure(error) else { return }
            if refreshFailure.makesStatusUnavailable {
                show(.unavailable)
            }
            warning.report(refreshFailure.failure, from: .refresh)
            Self.log.error("Background refresh failed with status \(refreshFailure.failure.result.status, privacy: .public)")
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
        state.sidebarFilter = sidebar.filter
        state.findText = commitColumns.history.findField.stringValue
        state.findField = commitColumns.history.find.searchField
        state.workingAreaFilter = commitColumns.workingArea.filter
        state.columns = columns.columns
        state.diffOptions = diffOptions.options
        state.showsMessageAsMarkdown = messageFormat.showsMarkdown
        state.diffPlaces = diffPlaces.memory
        state.historyPlaces = commitColumns.historyPlaces
        state.openWindows = openedWindows.openWindows
        state.commitDraft = commitColumns.workingArea.draft
        viewStates.set(state, for: repository)
    }

    private func show(_ titleBar: RepositoryTitleBar) {
        guard let window else { return }
        window.subtitle = titleBar.subtitle
        titleItem.title.subtitle = titleBar.subtitle
        window.isDocumentEdited = titleBar.isEdited
    }

}

/// How the columns and the windows opened from them reach the window.
extension RepositoryWindowController {
    fileprivate func connectSidebar() {
        pinning.window = window
        sidebar.openInNewWindow = { [weak self] item in self?.historyWindowCommand.open(item) }
        sidebar.onChange = { [weak self] in
            guard let self else { return }
            saveViewState()
            commitColumns.show(selection: sidebar.selection, contents: sidebar.contents)
        }
    }

    fileprivate func connectCommitColumns(restoring openWindows: OpenWindows) {
        messageFormat.onChange = { [weak self] in self?.saveViewState() }
        commitColumns.detail.messageFormat = messageFormat
        openedWindows.toRestore = openWindows
        openedWindows.onChange = { [weak self] in self?.saveViewState() }
        commitColumns.reveal = { [weak self] id in self?.revealInSidebar(id) }
        commitColumns.present = { [weak self] failure, retry in self?.present(failure, retry: retry) }
        commitColumns.open = { [weak self] commit in self?.openedWindows.openCommit(commit, from: self?.window) }
        commitColumns.openFileWindow = { [weak self] request in self?.openedWindows.openFile(request, from: self?.window) }
        let session = commitColumns.workingAreaSession
        session.queue.didRun = { [weak self] in self?.scheduler.requestNow(because: .commandRan) }
        session.queue.presentFailure = { [weak self] failure in self?.presentCommandFailure(failure) }
        session.editor.onDraftChange = { [weak self] _ in self?.saveViewState() }
        commitColumns.openWorkingArea = { [weak self] in self?.openWorkingAreaWindow() }
        commitColumns.onHistoryPlacesChange = { [weak self] in self?.saveViewState() }
        commitColumns.history.onFindChange = { [weak self] in self?.saveViewState() }
        commitColumns.workingArea.onFilterChange = { [weak self] in self?.saveViewState() }
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

    func openWorkingAreaWindow() {
        openedWindows.openWorkingArea(from: window)
    }

    /// Opened by the user from a warning or a column's Show Details, so it has a Try Again.
    fileprivate func present(_ failure: GitFailure, retry: @escaping () -> Void) {
        guard let window else { return }
        failureSheet.present(failure, repository: repository, on: window, wasOpenedByUser: true, retry: retry)
    }
}

/// Fetching, pulling and pushing, and what the app does after a fetch.
extension RepositoryWindowController {
    fileprivate func connectRemotes() {
        let didFetch = { [weak self] in
            self?.scheduler.requestNow(because: .commandRan)
            self?.commitGraph.addLayer()
        }
        remotes.connect(window: { [weak self] in self?.window }, failureSheet: failureSheet, warning: warning, didFetch: didFetch)
        warning.retry = { [weak self] source in
            switch source {
            case .refresh: self?.scheduler.requestNow(because: .retried)
            case .automaticFetch: self?.remotes.sync.fetch(nil, from: self?.window)
            }
        }
        remotes.start()
    }
}

/// Branches, stashes, tags and the history's commits, and where their failures show.
extension RepositoryWindowController {
    fileprivate func connectOperations() {
        let goToUncommittedChanges = { [weak self] in
            self?.showWindow(nil)
            self?.goToUncommittedChanges(nil)
        }
        let window = { [weak self] in self?.window }
        operations.connect(window: window, failureSheet: failureSheet, goToUncommittedChanges: goToUncommittedChanges)
        operations.attach(sidebar: sidebar, commitColumns: commitColumns, remotes: remotes)
    }
}
