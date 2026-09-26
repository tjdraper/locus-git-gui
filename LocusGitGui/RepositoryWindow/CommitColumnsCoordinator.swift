import Foundation

/// Keeps the history showing what the sidebar has selected, and the detail column showing what the
/// history has selected, with each commit's branches and tags labelled in both. The working area
/// sits at the top of every history.
final class CommitColumnsCoordinator {
    let history: HistoryViewController
    let detail: CommitDetailViewController
    let workingArea: WorkingAreaViewController
    let detailColumn: DetailColumnController
    var reveal: ((SidebarItemID) -> Void)?
    var open: ((Commit) -> Void)?
    var openFileWindow: ((FileWindowRequest) -> Void)?
    /// Every labelled commit's labels, as of the last refresh.
    private(set) var labels: [String: [CommitRefLabel]] = [:]
    var present: ((GitFailure, _ retry: @escaping () -> Void) -> Void)?

    /// As of the last refresh. Nil until the first.
    private var refs: [Ref]?
    private var head: RepositoryStatus.Branch?
    private var shownSelection: SidebarItemID?
    /// As of the last refresh.
    private var workingAreaSummary: WorkingAreaSummary?

    init(commands: RepositoryCommandRunner, diffOptions: DiffOptionsStore, commitDraft: CommitMessage?) {
        history = HistoryViewController(list: HistoryList { command, onOutput in
            try await commands.run(command, onOutput: onOutput)
        })
        detail = CommitDetailViewController(commands: commands, diffOptions: diffOptions)
        workingArea = WorkingAreaViewController(commands: commands, diffOptions: diffOptions, draft: commitDraft)
        detailColumn = DetailColumnController(commit: detail, workingArea: workingArea)
        history.onSelect = { [weak self] item in
            guard let self else { return }
            switch item {
            case .workingArea:
                detail.show(nil, labels: [])
                detailColumn.showWorkingArea(true)
            case let .commit(commit):
                detailColumn.showWorkingArea(false)
                detail.show(commit, labels: history.labels(of: commit))
            case nil:
                detailColumn.showWorkingArea(false)
                detail.show(nil, labels: [])
            }
        }
        history.reveal = { [weak self] id in self?.reveal?(id) }
        history.onOpen = { [weak self] commit in self?.open?(commit) }
        detail.reveal = { [weak self] id in self?.reveal?(id) }
        detail.goToCommit = { [weak self] hash in self?.history.goToCommit(hash) }
        detail.openFileWindow = { [weak self] request in self?.openFileWindow?(request) }
        history.showFailure = { [weak self] failure, retry in self?.present?(failure, retry) }
        detail.showFailure = { [weak self] failure, retry in self?.present?(failure, retry) }
        workingArea.showFailure = { [weak self] failure, retry in self?.present?(failure, retry) }
        workingArea.openFileWindow = { [weak self] request in self?.openFileWindow?(request) }
    }

    /// After each refresh, before the history is shown, so a repository with no commits yet still
    /// has its working area to make the first one in.
    func show(_ snapshot: RepositorySnapshot) {
        workingAreaSummary = WorkingAreaSummary(snapshot.status)
        workingArea.show(snapshot)
    }

    /// After each refresh.
    func show(refs: [Ref], head: RepositoryStatus.Branch, selection: SidebarItemID?, contents: SidebarContents?) {
        self.refs = refs
        self.head = head
        show(selection: selection, contents: contents)
    }

    /// Whenever the sidebar changes, once the repository has been read.
    func show(selection: SidebarItemID?, contents: SidebarContents?) {
        guard let refs, let head else { return }
        history.show(
            HistoryScope.resolve(selection: selection, refs: refs, contents: contents, head: head.commit),
            isSameSelection: selection == shownSelection
        )
        shownSelection = selection
        history.showWorkingArea(HistoryScope.isCheckedOut(selection: selection, branch: head.name) ? workingAreaSummary : nil)
        labels = CommitRefLabel.byCommit(refs: refs, detachedHead: head.name == nil ? head.commit : nil)
        history.showLabels(labels)
        if let commit = detail.commit {
            detail.showLabels(labels[commit.hash] ?? [])
        }
    }

    /// Commands for the history, the commit or the working area reach them from whichever column
    /// has focus.
    func target(forAction action: Selector) -> Any? {
        if HistoryViewController.windowActions.contains(action) {
            return history
        }
        if CommitDetailViewController.windowActions.contains(action) {
            return detail
        }
        if WorkingAreaViewController.windowActions.contains(action) {
            return workingArea
        }
        if DiffViewController.windowActions.contains(action) {
            return detailColumn.diff
        }
        return nil
    }
}
