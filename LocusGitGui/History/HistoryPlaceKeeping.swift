import AppKit

/// Where the history was left, for the window to remember for each sidebar item, and to show the
/// history there again when the user comes back to it.
extension HistoryViewController {
    private static let placeReportDelay: Duration = .milliseconds(300)

    var place: HistoryPlace {
        let selection: HistoryPlace.Selection? = isWorkingAreaSelected ? .workingArea : selectedCommit.map { .commit($0.hash) }
        let isAtTop = table.visibleRect.minY <= 0
        let topCommit = isAtTop ? nil : commit(at: table.rows(in: table.visibleRect).location)?.hash
        return HistoryPlace(selection: selection, topCommit: topCommit)
    }

    /// A moment later, since scrolling changes it many times a second. Nothing is told while a
    /// place is waiting to be shown, which would only be the history on its way there.
    func placeDidChange() {
        guard onPlaceChange != nil, pendingPlace == nil, reportingPlace == nil else { return }
        reportingPlace = Task { [weak self] in
            try? await Task.sleep(for: Self.placeReportDelay)
            guard !Task.isCancelled else { return }
            self?.reportPlaceNow()
        }
    }

    /// Before the history changes, while the window still knows which history this was.
    func reportPlaceNow() {
        guard let reporting = reportingPlace else { return }
        reporting.cancel()
        reportingPlace = nil
        onPlaceChange?(place)
    }

    func observeScrolling() {
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        scrollWatch = NotificationWatch(NSView.boundsDidChangeNotification, object: clipView) { [weak self] in
            self?.placeDidChange()
        }
    }

    /// Once the history it was left in has been read. A selected commit further down than has been
    /// read is read on down to quietly, since the user didn't ask to go anywhere.
    func show(_ place: HistoryPlace) {
        if let top = place.topCommit.flatMap(list.index(of:)) {
            table.scroll(NSPoint(x: 0, y: table.rect(ofRow: row(ofCommit: top)).minY))
        } else if table.numberOfRows > 0 {
            table.scrollRowToVisible(0)
        }
        switch place.selection {
        case .workingArea where workingArea != nil:
            table.selectRowIndexes([0], byExtendingSelection: false)
        case let .commit(hash):
            if let index = list.index(of: hash) {
                table.selectRowIndexes([row(ofCommit: index)], byExtendingSelection: false)
            } else {
                table.deselectAll(nil)
                navigator.goTo(hash, quietly: true)
            }
        case .workingArea, nil:
            table.deselectAll(nil)
        }
    }
}
