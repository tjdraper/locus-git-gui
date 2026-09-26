import AppKit

/// Files picked to act on together, as files are picked in a Finder list: ⌘-click adds or removes
/// one, and Shift-click or Shift-J/K takes in the range from the last one picked. The current file
/// moves with the picking, and Escape lets go of them all.
extension DiffViewController {
    /// The picked files in the diff's order, or the current file when none are picked.
    var filesToActOn: [DiffFile] {
        guard !selectedFiles.isEmpty else { return currentFile.map { [$0] } ?? [] }
        return files.filter { selectedFiles.contains($0.id) }
    }

    /// A file's own buttons act on every picked file when it's one of them.
    func filesToActOn(from file: DiffFile) -> [DiffFile] {
        selectedFiles.contains(file.id) ? filesToActOn : [file]
    }

    func toggleSelection(of id: DiffFile.Identity) {
        if selectedFiles.contains(id) {
            selectedFiles.remove(id)
        } else {
            selectedFiles.insert(id)
        }
        selectionAnchor = id
        markedFile = id
        blockViews.update()
    }

    func extendSelection(to id: DiffFile.Identity) {
        guard let anchor = selectionAnchor ?? currentFile?.id,
              let start = index(of: anchor), let end = index(of: id) else { return }
        selectionAnchor = anchor
        selectedFiles = Set(files[min(start, end) ... max(start, end)].map(\.id))
        markedFile = id
        blockViews.update()
    }

    /// From the current file to the next or previous one, as Shift and an arrow do in a list.
    func extendSelection(offset: Int) {
        guard let current = currentFile?.id else { return }
        let anchor = selectionAnchor ?? current
        goToFile(offset: offset)
        selectionAnchor = anchor
        guard let moved = markedFile else { return }
        extendSelection(to: moved)
    }

    func clearFileSelection() {
        guard !selectedFiles.isEmpty || selectionAnchor != nil else { return }
        selectedFiles = []
        selectionAnchor = nil
        blockViews.update()
    }

    /// After the diff is read again, such as once the picked files are staged and move to the
    /// staged group, where they're other files.
    func keepSelectedFilesStillShown() {
        let shown = Set(files.map(\.id))
        selectedFiles.formIntersection(shown)
        if let anchor = selectionAnchor, !shown.contains(anchor) {
            selectionAnchor = nil
        }
    }
}
