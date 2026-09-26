import Foundation

/// Keeps the history showing what the sidebar has selected, and the detail column showing what the
/// history has selected, with each commit's branches and tags labelled in both.
final class CommitColumnsCoordinator {
    let history: HistoryViewController
    let detail: CommitDetailViewController
    var reveal: ((SidebarItemID) -> Void)?
    var open: ((Commit) -> Void)?
    /// Every labelled commit's labels, as of the last refresh.
    private(set) var labels: [String: [CommitRefLabel]] = [:]
    var present: ((GitFailure, _ retry: @escaping () -> Void) -> Void)?

    /// As of the last refresh. Nil until the first.
    private var refs: [Ref]?
    private var head: RepositoryStatus.Branch?
    private var shownSelection: SidebarItemID?

    init(commands: RepositoryCommandRunner) {
        history = HistoryViewController(list: HistoryList { command, onOutput in
            try await commands.run(command, onOutput: onOutput)
        })
        detail = CommitDetailViewController { try await commands.run($0) }
        history.onSelect = { [weak self] commit in
            guard let self else { return }
            detail.show(commit, labels: commit.map(history.labels) ?? [])
        }
        history.reveal = { [weak self] id in self?.reveal?(id) }
        history.onOpen = { [weak self] commit in self?.open?(commit) }
        detail.reveal = { [weak self] id in self?.reveal?(id) }
        detail.goToCommit = { [weak self] hash in self?.history.goToCommit(hash) }
        history.showFailure = { [weak self] failure, retry in self?.present?(failure, retry) }
        detail.showFailure = { [weak self] failure, retry in self?.present?(failure, retry) }
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
        labels = CommitRefLabel.byCommit(refs: refs, detachedHead: head.name == nil ? head.commit : nil)
        history.showLabels(labels)
        if let commit = detail.commit {
            detail.showLabels(labels[commit.hash] ?? [])
        }
    }

    /// Commands for the history or the commit reach them from whichever column has focus.
    func target(forAction action: Selector) -> Any? {
        if HistoryViewController.windowActions.contains(action) {
            return history
        }
        if CommitDetailViewController.windowActions.contains(action) {
            return detail
        }
        return nil
    }
}
