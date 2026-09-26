import AppKit

/// The windows opened from a repository's window: its commits', its files', its working area's and
/// its Activity. They name the repository as its tab does, keep up with its refreshes, and close
/// with it.
final class OpenedWindowsCoordinator {
    /// Brings the repository's window forward to show something in its sidebar.
    var reveal: ((SidebarItemID) -> Void)?
    var showFailure: ((GitFailure, NSWindow, _ retry: @escaping () -> Void) -> Void)?
    private var repositoryName: String
    private let commits: CommitWindowCoordinator
    private let files: FileWindowCoordinator
    private let workingArea: WorkingAreaWindowCoordinator
    private let activity: ActivityWindowPresenter

    init(
        commands: RepositoryCommandRunner,
        diffOptions: DiffOptionsStore,
        collapsedFiles: CollapsedFilesStore,
        session: WorkingAreaSession,
        repositoryName: String,
        repositoryWindow: RepositoryWindowController
    ) {
        self.repositoryName = repositoryName
        commits = CommitWindowCoordinator(
            commands: commands,
            diffOptions: diffOptions,
            collapsedFiles: collapsedFiles,
            repositoryWindow: repositoryWindow
        )
        files = FileWindowCoordinator(commands: commands, diffOptions: diffOptions, repositoryWindow: repositoryWindow)
        workingArea = WorkingAreaWindowCoordinator(
            commands: commands,
            diffOptions: diffOptions,
            collapsedFiles: collapsedFiles,
            session: session,
            repositoryWindow: repositoryWindow
        )
        activity = ActivityWindowPresenter(log: commands.log, repositoryName: repositoryName)
        commits.reveal = { [weak self] id in self?.reveal?(id) }
        commits.openFileWindow = { [weak self] request, window in self?.openFile(request, from: window) }
        workingArea.openFileWindow = { [weak self] request, window in self?.openFile(request, from: window) }
        workingArea.showFailure = { [weak self] failure, window, retry in self?.showFailure?(failure, window, retry) }
    }

    var workingAreaWindow: NSWindow? {
        workingArea.window
    }

    func openCommit(_ commit: Commit, from window: NSWindow?) {
        commits.show(commit, from: window, repositoryName: repositoryName)
    }

    func openFile(_ request: FileWindowRequest, from window: NSWindow?) {
        files.show(request, from: window, repositoryName: repositoryName)
    }

    func openWorkingArea(from window: NSWindow?) {
        workingArea.show(from: window, repositoryName: repositoryName)
    }

    func showActivity() {
        activity.show()
    }

    func showRepositoryName(_ name: String) {
        repositoryName = name
        commits.showRepositoryName(name)
        files.showRepositoryName(name)
        workingArea.showRepositoryName(name)
        activity.showRepositoryName(name)
    }

    /// After every refresh. The working area's files are only listed when a file window shows one.
    func show(_ snapshot: RepositorySnapshot, workingAreaFiles: () -> [DiffFile]) {
        workingArea.show(snapshot)
        if files.showsWorkingArea {
            files.showWorkingArea(workingAreaFiles())
        }
    }

    func showLabels(_ labels: [String: [CommitRefLabel]]) {
        commits.showLabels(labels)
    }

    func closeAll() {
        activity.close()
        commits.closeAll()
        files.closeAll()
        workingArea.close()
    }
}
