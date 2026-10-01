import AppKit

/// What can be done with one file in the diff, from its header, its menu or the menu bar.
extension DiffViewController {
    var commandTarget: DiffCommandTarget? {
        guard let content = canvas.content else { return nil }
        return DiffCommandTarget(
            document: content.document,
            layout: content.layout,
            selection: canvas.selection,
            visibleTop: canvas.visibleRect.minY + content.layout.metrics.headerHeight
                + DiffStickyHeadings.cover(atTop: canvas.visibleRect.minY, document: content.document, layout: content.layout),
            visibleBottom: canvas.visibleRect.maxY,
            markedFile: markedFile.flatMap(index(of:))
        )
    }

    func isInWorkingTree(_ path: String) -> Bool {
        if let known = workingTreePresence[path] {
            return known
        }
        let exists = WorkingTreeFile(path: path, in: workTree).exists
        workingTreePresence[path] = exists
        return exists
    }

    func openInEditor(path: String) {
        let file = WorkingTreeFile(path: path, in: workTree)
        guard file.exists else {
            NSSound.beep()
            return
        }
        file.openInEditor()
    }

    func openFileWindow(_ id: DiffFile.Identity) {
        guard opensFileWindows, let index = index(of: id) else { return }
        openFileWindow?(files[index])
    }

    func menu(forFile index: Int) -> ChangedFileMenu {
        let id = files[index].id
        let path = id.path
        let file = WorkingTreeFile(path: path, in: workTree)
        return ChangedFileMenu(
            actions: fileActions?(files[index]) ?? [],
            isInWorkingTree: isInWorkingTree(path),
            opensFileWindows: opensFileWindows,
            isCollapsed: collapsedFiles.contains(id),
            openInEditor: { [weak self] in self?.openInEditor(path: path) },
            revealInFinder: file.revealInFinder,
            copyAbsolutePath: file.copyAbsolutePath,
            copyPathFromRepositoryRoot: file.copyPathFromRepositoryRoot,
            openFileWindow: { [weak self] in self?.openFileWindow(id) },
            toggleCollapsed: { [weak self] in self?.toggleCollapsed(id) }
        )
    }
}
