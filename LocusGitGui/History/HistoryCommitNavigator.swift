import AppKit

/// Takes the history to a commit, such as a parent well below its child, reading on down the
/// history to reach it. A commit it can't reach is offered in a window of its own instead.
final class HistoryCommitNavigator {
    private let list: HistoryList
    private let table: NSTableView
    /// A commit's row, which comes after the working area's.
    private let rowForCommit: (Int) -> Int
    private let focusList: () -> Void
    private let open: (Commit) -> Void
    private var going: Task<Void, Never>?

    init(
        list: HistoryList,
        table: NSTableView,
        rowForCommit: @escaping (Int) -> Int,
        focusList: @escaping () -> Void,
        open: @escaping (Commit) -> Void
    ) {
        self.list = list
        self.table = table
        self.rowForCommit = rowForCommit
        self.focusList = focusList
        self.open = open
    }

    /// A newer go-to, or the user choosing another commit, cancels one still reading. `quietly` goes
    /// there without taking focus, and says nothing when the commit can't be reached.
    func goTo(_ hash: String, quietly: Bool = false) {
        going?.cancel()
        // A search's results rarely hold a commit's parent, and reading on through all of them to
        // be sure would search the history again for every page.
        if list.search != nil, list.index(of: hash) == nil {
            if !quietly {
                showOutOfReach(hash, because: .notInSearch)
            }
            return
        }
        going = Task { [weak self] in
            guard let result = await self?.list.find(hash), !Task.isCancelled, let self else { return }
            switch result {
            case let .found(index):
                table.selectRowIndexes([rowForCommit(index)], byExtendingSelection: false)
                table.scrollRowToVisible(rowForCommit(index))
                if !quietly {
                    focusList()
                }
            case _ where quietly:
                return
            case .tooFar:
                showOutOfReach(hash, because: .tooFar)
            case .missing:
                showOutOfReach(hash, because: .notInHistory)
            }
        }
    }

    func cancel() {
        going?.cancel()
    }

    /// Its own window needs only that one commit read.
    private func showOutOfReach(_ hash: String, because reason: CommitOutOfReachAlert.Reason) {
        guard let window = table.window else { return }
        CommitOutOfReachAlert.present(for: hash, because: reason, on: window) { [weak self] in
            Task { [weak self] in
                guard let commit = await self?.list.readCommit(hash) else {
                    NSSound.beep()
                    return
                }
                self?.open(commit)
            }
        }
    }
}
