import AppKit

/// The working area's row, which comes before every commit's.
extension HistoryViewController {
    /// After every refresh and every change of history. Nil takes the row away, for a history that
    /// isn't the checked-out branch's. The row is selected when it comes in, unless something else
    /// already is, since it's where the user most often starts.
    func showWorkingArea(_ summary: WorkingAreaSummary?) {
        guard summary != workingArea else { return }
        guard let summary else {
            removeWorkingArea()
            return
        }
        let isNew = workingArea == nil
        workingArea = summary
        guard isNew else {
            table.reloadData(forRowIndexes: [0], columnIndexes: [0])
            return
        }
        isRestoringSelection = true
        table.insertRows(at: [0])
        isRestoringSelection = false
        updatePlaceholder()
        if selectedCommit == nil {
            selectWorkingArea()
        }
    }

    private func removeWorkingArea() {
        let wasSelected = isWorkingAreaSelected
        isRestoringSelection = true
        workingArea = nil
        table.removeRows(at: [0])
        isRestoringSelection = false
        updatePlaceholder()
        guard wasSelected else { return }
        isWorkingAreaSelected = false
        onSelect?(nil)
    }

    /// Selects the working area's row and scrolls to it.
    func selectWorkingArea() {
        guard workingArea != nil else { return }
        navigator.cancel()
        table.selectRowIndexes([0], byExtendingSelection: false)
        table.scrollRowToVisible(0)
    }

    /// The working area's row comes before the first commit's.
    var commitRowOffset: Int {
        workingArea == nil ? 0 : 1
    }

    func row(ofCommit index: Int) -> Int {
        index + commitRowOffset
    }

    func isWorkingAreaRow(_ row: Int) -> Bool {
        workingArea != nil && row == 0
    }
}
