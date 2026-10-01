import Foundation

/// Moving through the review's files and checking them off as they're read.
extension ReviewSession {
    /// Whether every file picked is checked off, for a command that checks them all or unchecks
    /// them all.
    var isSelectionReviewed: Bool {
        let picked = selectedEntries
        return !picked.isEmpty && picked.allSatisfy { $0.state == .checked }
    }

    /// Checks off the files picked, or unchecks them when they're all checked already.
    func toggleSelectionReviewed() {
        setReviewed(Set(selectedEntries.map(\.file.path)), !isSelectionReviewed)
    }

    /// The next file not yet checked off after the one shown, going round to the start.
    var nextUncheckedPath: String? {
        let files = entries
        let start = files.firstIndex { $0.file.path == selectedPath } ?? -1
        let after = files[(start + 1)...] + files[..<max(start, 0)]
        return after.first { $0.state != .checked }?.file.path
    }

    /// Checks off the file shown and moves on to the next one not yet checked. With several picked,
    /// checks them all off and stays.
    func checkAndMoveOn() {
        guard selectedEntry != nil else {
            toggleSelectionReviewed()
            return
        }
        let wasChecked = isSelectionReviewed
        let next = nextUncheckedPath
        toggleSelectionReviewed()
        if !wasChecked, let next {
            selection = [next]
        }
    }

    func move(by offset: Int) -> Bool {
        let files = entries
        guard let index = files.firstIndex(where: { $0.file.path == selectedPath }), files.indices.contains(index + offset) else {
            return false
        }
        selection = [files[index + offset].file.path]
        return true
    }

    func canMove(by offset: Int) -> Bool {
        let files = entries
        guard let index = files.firstIndex(where: { $0.file.path == selectedPath }) else { return false }
        return files.indices.contains(index + offset)
    }
}
