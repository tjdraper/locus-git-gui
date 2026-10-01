import AppKit

/// The Review menu's commands for the file in front, and the same on the file's header.
extension ReviewWindowController: NSMenuItemValidation {
    /// Checking the file off, and for a file changed since it was reviewed, which changes to show.
    func fileActions() -> [DiffAction] {
        guard let entry = session.selectedEntry else { return [] }
        var actions: [DiffAction] = []
        let path = entry.file.path
        if entry.state == .changedSinceReviewed, canShowChangesSince(entry) {
            let isSince = !session.showsWholeDiff.contains(path)
            actions.append(DiffAction(
                title: "Only Changes Since Reviewed",
                toolTip: "Show only what changed since you last reviewed this file",
                isOn: isSince
            ) { [weak self] in self?.toggleChangesSince(path) })
        }
        actions.append(DiffAction(
            title: "Reviewed",
            menuTitle: entry.state == .checked ? "Mark as Not Reviewed" : "Mark as Reviewed",
            toolTip: "Space checks this file off and moves on to the next",
            isOn: entry.state == .checked
        ) { [weak self] in self?.session.toggleCheck(path) })
        actions.append(DiffAction(title: "Comment on File", isInMenuOnly: true) { [weak self] in self?.startFileComment(path) })
        return actions
    }

    func toggleChangesSince(_ path: String) {
        if session.showsWholeDiff.contains(path) {
            session.showsWholeDiff.remove(path)
        } else {
            session.showsWholeDiff.insert(path)
        }
        showSelection(force: true)
        onChange?()
    }

    func canShowChangesSince(_ entry: ReviewSession.Entry) -> Bool {
        session.review?.checks.reviewedVersion(of: entry.file.path)?.newObject != nil && entry.file.newObject != nil
    }

    func showsChangesSince(_ entry: ReviewSession.Entry) -> Bool {
        entry.state == .changedSinceReviewed && canShowChangesSince(entry) && !session.showsWholeDiff.contains(entry.file.path)
    }

    @objc func markFileReviewed(_: Any?) {
        session.checkAndMoveOn()
    }

    @objc func goToNextUnreviewedFile(_: Any?) {
        guard let next = session.nextUncheckedPath else {
            NSSound.beep()
            return
        }
        session.selection = next
    }

    @objc func showChangesSinceReviewed(_: Any?) {
        guard let path = session.selection else { return }
        toggleChangesSince(path)
    }

    /// On the lines selected, or else on the file shown.
    @objc func addReviewComment(_: Any?) {
        startComment()
    }

    /// Every unresolved comment, to paste where the review's author will see it.
    @objc func copyReviewComments(_: Any?) {
        guard let review = session.review else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ReviewMarkdown.unresolvedComments(of: review), forType: .string)
    }

    @objc func renameReview(_: Any?) {
        onRename?()
    }

    @objc func deleteReview(_: Any?) {
        onDelete?()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let entry = session.selectedEntry
        switch menuItem.action {
        case #selector(markFileReviewed(_:)):
            menuItem.title = entry?.state == .checked ? "Mark as Not Reviewed" : AppCommand.markFileReviewed.title
            return entry != nil && !isLocked
        case #selector(addReviewComment(_:)):
            menuItem.title = diff.selectedLineTarget.map { "Comment on \(ReviewLineAnchor.label($0.lines))" } ?? "Comment on File"
            return entry != nil && !isLocked
        case #selector(copyReviewComments(_:)):
            return (session.review?.unresolvedThreads ?? 0) > 0
        case #selector(goToNextUnreviewedFile(_:)):
            return session.nextUncheckedPath != nil && !isLocked
        case #selector(showChangesSinceReviewed(_:)):
            guard let entry, entry.state == .changedSinceReviewed, canShowChangesSince(entry) else {
                menuItem.state = .off
                return false
            }
            menuItem.state = session.showsWholeDiff.contains(entry.file.path) ? .off : .on
            return !isLocked
        default:
            return true
        }
    }
}
