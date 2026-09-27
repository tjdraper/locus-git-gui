import AppKit

/// Collapsing and expanding files, from their headers and the summary bar.
extension DiffViewController {
    func toggleCollapsed(_ id: DiffFile.Identity) {
        if collapsedFiles.contains(id) {
            collapsedFiles.remove(id)
        } else {
            collapsedFiles.insert(id)
        }
        rebuildKeepingHeader(of: id)
    }

    /// Collapsed or expanded somewhere else showing the same diff.
    func showCollapsedFiles(_ collapsed: Set<DiffFile.Identity>) {
        guard collapsed != collapsedFiles else { return }
        collapsedFiles = collapsed
        rebuild(keepingPlace: true)
    }

    /// Option-click, as in Finder: every file goes the way the clicked one would.
    func toggleAllCollapsed(like id: DiffFile.Identity) {
        collapsedFiles = collapsedFiles.contains(id) ? [] : Set(files.map(\.id))
        rebuildKeepingHeader(of: id)
    }

    /// Keeps a file's header where it was on screen when the file collapses or expands under it,
    /// or at the top when it was stuck there.
    func rebuildKeepingHeader(of id: DiffFile.Identity) {
        guard let content = canvas.content, let file = index(of: id) else {
            rebuild(keepingPlace: true)
            return
        }
        let distance = max(content.layout.top(of: content.document.fileStarts[file]) - canvas.visibleRect.minY, 0)
        rebuild(keepingPlace: false)
        guard let rebuilt = canvas.content else { return }
        canvas.scroll(to: rebuilt.layout.top(of: rebuilt.document.fileStarts[file]) - distance)
        blockViews.update()
    }
}
