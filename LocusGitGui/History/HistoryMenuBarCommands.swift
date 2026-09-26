import AppKit

/// The Commit and Find commands, which reach the history from whichever column has focus.
extension HistoryViewController {
    /// Edit > Copy with the list focused copies the selected commit's hash.
    @objc func copy(_: Any?) {
        copyCommitHash(nil)
    }

    /// A double-click, on a commit or the working area.
    @objc func openClickedCommit(_: Any?) {
        if isWorkingAreaRow(table.clickedRow) {
            onOpenWorkingArea?()
            return
        }
        guard let commit = commit(at: table.clickedRow) else { return }
        onOpen?(commit)
    }

    /// The working area too, when its row is selected.
    @objc func openCommitInNewWindow(_: Any?) {
        if isWorkingAreaSelected {
            onOpenWorkingArea?()
            return
        }
        guard let selectedCommit else { return }
        onOpen?(selectedCommit)
    }

    @objc func copyCommitHash(_: Any?) {
        guard let selectedCommit else { return }
        putOnPasteboard(selectedCommit.hash)
    }

    @objc func copyCommitSubject(_: Any?) {
        guard let selectedCommit else { return }
        putOnPasteboard(selectedCommit.subject)
    }

    @objc func findInHistory(_: Any?) {
        focusFind(searching: nil)
    }

    @objc func findByMessage(_: Any?) {
        focusFind(searching: .message)
    }

    @objc func findByAuthor(_: Any?) {
        focusFind(searching: .author)
    }

    @objc func findInChanges(_: Any?) {
        focusFind(searching: .changes)
    }
}

extension HistoryViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)), #selector(copyCommitHash(_:)), #selector(copyCommitSubject(_:)):
            return selectedCommit != nil
        case #selector(openCommitInNewWindow(_:)):
            return selectedCommit != nil || isWorkingAreaSelected
        case #selector(findByMessage(_:)):
            menuItem.state = find.searchField == .message ? .on : .off
        case #selector(findByAuthor(_:)):
            menuItem.state = find.searchField == .author ? .on : .off
        case #selector(findInChanges(_:)):
            menuItem.state = find.searchField == .changes ? .on : .off
        default:
            break
        }
        return true
    }
}
