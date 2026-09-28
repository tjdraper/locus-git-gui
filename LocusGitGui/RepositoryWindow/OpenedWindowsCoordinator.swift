import AppKit

/// The windows opened from a repository's window: its commits', its files', its branches' and
/// other histories, its working area's, its conflicts' and its Activity. They name the repository
/// as its tab does, keep up with its refreshes, close with it, and open again with it, where they
/// were left.
final class OpenedWindowsCoordinator {
    /// Brings the repository's window forward to show something in its sidebar.
    var reveal: ((SidebarItemID) -> Void)?
    var showFailure: ((GitFailure, NSWindow, _ retry: @escaping () -> Void) -> Void)?
    /// When a window opens, closes, moves or shows something else, for the repository to remember.
    var onChange: (() -> Void)?
    /// The windows to open again once the repository has been read, which stand for the open windows
    /// until they have been.
    var toRestore: OpenWindows?
    private var isRestoring = false
    /// While the repository's window closes them, which isn't the user closing them one at a time.
    private var isClosingAll = false
    private let commands: RepositoryCommandRunner
    private let diffOptions: DiffOptionsStore
    private var repositoryName: String
    private let commits: CommitWindowCoordinator
    private let files: FileWindowCoordinator
    private let histories: HistoryWindowCoordinator
    private let workingArea: WorkingAreaWindowCoordinator
    private let conflicts: ConflictWindowCoordinator
    private let activity: ActivityWindowPresenter
    private lazy var conflictCommand = ConflictWindowCommand(
        canShow: { [weak self] in self?.conflicts.hasConflicts == true || self?.conflicts.window != nil },
        show: { [weak self] in self?.showConflicts(from: NSApp.keyWindow) }
    )

    init(
        commands: RepositoryCommandRunner,
        diffOptions: DiffOptionsStore,
        diffPlaces: DiffPlaceStore,
        session: WorkingAreaSession,
        operationStatus: OperationStatus,
        repositoryName: String,
        repositoryWindow: RepositoryWindowController
    ) {
        self.repositoryName = repositoryName
        self.commands = commands
        self.diffOptions = diffOptions
        commits = CommitWindowCoordinator(
            commands: commands,
            diffOptions: diffOptions,
            diffPlaces: diffPlaces,
            repositoryWindow: repositoryWindow
        )
        files = FileWindowCoordinator(commands: commands, diffOptions: diffOptions, repositoryWindow: repositoryWindow)
        histories = HistoryWindowCoordinator(
            commands: commands,
            diffOptions: diffOptions,
            diffPlaces: diffPlaces,
            repositoryWindow: repositoryWindow
        )
        workingArea = WorkingAreaWindowCoordinator(
            commands: commands,
            diffOptions: diffOptions,
            diffPlaces: diffPlaces,
            session: session,
            repositoryWindow: repositoryWindow
        )
        conflicts = ConflictWindowCoordinator(
            commands: commands,
            queue: session.queue,
            operationStatus: operationStatus,
            repositoryWindow: repositoryWindow
        )
        activity = ActivityWindowPresenter(log: commands.log, repositoryName: repositoryName)
        commits.reveal = { [weak self] id in self?.reveal?(id) }
        commits.openFileWindow = { [weak self] request, window in self?.openFile(request, from: window) }
        workingArea.openFileWindow = { [weak self] request, window in self?.openFile(request, from: window) }
        workingArea.showFailure = { [weak self] failure, window, retry in self?.showFailure?(failure, window, retry) }
        conflicts.showFailure = { [weak self] failure, window, retry in self?.showFailure?(failure, window, retry) }
        histories.reveal = { [weak self] id in self?.reveal?(id) }
        histories.openCommit = { [weak self] commit, window in self?.openCommit(commit, from: window) }
        histories.openFileWindow = { [weak self] request, window in self?.openFile(request, from: window) }
        histories.onChange = { [weak self] in self?.windowsChanged() }
        commits.onChange = { [weak self] in self?.windowsChanged() }
        files.onChange = { [weak self] in self?.windowsChanged() }
        workingArea.onChange = { [weak self] in self?.windowsChanged() }
        conflicts.onChange = { [weak self] in self?.windowsChanged() }
        activity.onChange = { [weak self] in self?.windowsChanged() }
    }

    var openWindows: OpenWindows {
        if let toRestore {
            return toRestore
        }
        return OpenWindows(
            commits: commits.records,
            files: files.records,
            histories: histories.records,
            workingArea: workingArea.record,
            conflicts: conflicts.record,
            isActivityShown: activity.isShown
        )
    }

    private func windowsChanged() {
        guard !isClosingAll, toRestore == nil else { return }
        onChange?()
    }

    var workingAreaWindow: NSWindow? {
        workingArea.window
    }

    var conflictWindow: NSWindow? {
        conflicts.window
    }

    /// View > Show Conflicts, from any of the repository's windows.
    func target(forAction action: Selector) -> Any? {
        ConflictWindowCommand.actions.contains(action) ? conflictCommand : nil
    }

    func openCommit(_ commit: Commit, from window: NSWindow?) {
        commits.show(commit, from: window, repositoryName: repositoryName)
    }

    func openFile(_ request: FileWindowRequest, from window: NSWindow?) {
        files.show(request, from: window, repositoryName: repositoryName)
    }

    func openHistory(of item: SidebarItemID, from window: NSWindow?) {
        histories.show(item, from: window, repositoryName: repositoryName)
    }

    func openWorkingArea(from window: NSWindow?) {
        workingArea.show(from: window, repositoryName: repositoryName)
    }

    /// With `file` picked in its list, when it has a conflict.
    @discardableResult
    func showConflicts(file: String? = nil, from window: NSWindow?) -> NSWindow? {
        conflicts.show(file: file, from: window, repositoryName: repositoryName)
    }

    func showActivity() {
        activity.show()
    }

    func showRepositoryName(_ name: String) {
        repositoryName = name
        commits.showRepositoryName(name)
        files.showRepositoryName(name)
        histories.showRepositoryName(name)
        workingArea.showRepositoryName(name)
        conflicts.showRepositoryName(name)
        activity.showRepositoryName(name)
    }

    /// After every refresh. The working area's files are only listed when a file window shows one.
    func show(_ snapshot: RepositorySnapshot, workingAreaFiles: () -> [DiffFile]) {
        workingArea.show(snapshot)
        conflicts.show(snapshot)
        if files.showsWorkingArea {
            files.showWorkingArea(workingAreaFiles())
        }
    }

    /// After every refresh, once the repository's refs have been read.
    func show(refs: [Ref], head: String?, contents: SidebarContents, labels: [String: [CommitRefLabel]]) {
        commits.showLabels(labels)
        histories.show(refs: refs, head: head, contents: contents, labels: labels)
        conflicts.show(refs: refs)
    }

    func closeAll() {
        isClosingAll = true
        activity.close()
        commits.closeAll()
        files.closeAll()
        histories.closeAll()
        workingArea.close()
        conflicts.close()
    }

    /// Once the repository has been read, so the working area's files are known. Commits that are
    /// gone, working area files with no changes now, and the conflict window once there's nothing
    /// to resolve, are left closed.
    func restoreIfNeeded(from window: NSWindow?, workingAreaFiles: () -> [DiffFile]) {
        guard let record = toRestore, !isRestoring else { return }
        isRestoring = true
        if let workingAreaRecord = record.workingArea {
            workingArea.show(from: window, repositoryName: repositoryName, record: workingAreaRecord)
        }
        if let conflictRecord = record.conflicts, conflicts.hasConflicts {
            conflicts.show(from: window, repositoryName: repositoryName, record: conflictRecord)
        }
        if record.isActivityShown {
            activity.show()
        }
        for historyRecord in record.histories {
            histories.show(historyRecord.item, from: window, repositoryName: repositoryName, record: historyRecord)
        }
        let changes = record.files.contains { $0.commit == nil } ? workingAreaFiles() : []
        for fileRecord in record.files where fileRecord.commit == nil {
            guard let file = changes.first(where: { $0.id == fileRecord.file }) else { continue }
            let request = FileWindowRequest(source: .workingArea, file: file, files: changes)
            files.show(request, from: window, repositoryName: repositoryName, record: fileRecord)
        }
        Task { [weak self, weak window] in
            await self?.restoreCommitWindows(record, from: window)
            self?.toRestore = nil
            self?.onChange?()
        }
    }

    private func restoreCommitWindows(_ record: OpenWindows, from window: NSWindow?) async {
        for commitRecord in record.commits {
            guard let commit = await readCommit(commitRecord.commit) else { continue }
            commits.show(commit, from: window, repositoryName: repositoryName, frame: commitRecord.frame)
        }
        for fileRecord in record.files {
            guard let hash = fileRecord.commit, let commit = await readCommit(hash),
                  let detail = try? await CommitDetail.read(
                      hash,
                      options: diffOptions.options,
                      running: commands.run,
                      readingPatch: commands.readPatch
                  ),
                  let file = detail.files.first(where: { $0.id == fileRecord.file })
            else { continue }
            let request = FileWindowRequest(source: .commit(commit), file: file, files: detail.files)
            files.show(request, from: window, repositoryName: repositoryName, record: fileRecord)
        }
    }

    private func readCommit(_ hash: String) async -> Commit? {
        try? await HistoryReader.readHashMatch(hash, running: commands.run)
    }
}
