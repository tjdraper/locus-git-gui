import AppKit

/// The menu bar's diff commands, which act on the current file: the one with the selection in it,
/// or the one at the top of the view. The window passes them on from whichever column has focus.
extension DiffViewController {
    static let windowActions: Set<Selector> = [
        #selector(collapseFile(_:)),
        #selector(expandFile(_:)),
        #selector(collapseAllFiles(_:)),
        #selector(expandAllFiles(_:)),
        #selector(goToNextFile(_:)),
        #selector(goToPreviousFile(_:)),
        #selector(toggleIgnoreWhitespace(_:)),
        #selector(showMoreContext(_:)),
        #selector(showLessContext(_:)),
        #selector(openInEditor(_:)),
        #selector(revealChangedFileInFinder(_:)),
        #selector(copyAbsolutePath(_:)),
        #selector(copyPathFromRepositoryRoot(_:)),
        #selector(openFileInNewWindow(_:)),
    ]

    /// The file the menu bar's file commands act on.
    var currentFile: DiffFile? {
        commandTarget?.file.map { files[$0] }
    }

    private var currentPath: String? {
        currentFile?.changed.path
    }

    @objc func collapseFile(_: Any?) {
        guard let id = currentFile?.id, !collapsedFiles.contains(id) else { return }
        toggleCollapsed(id)
    }

    @objc func expandFile(_: Any?) {
        guard let id = currentFile?.id, collapsedFiles.contains(id) else { return }
        toggleCollapsed(id)
    }

    @objc func collapseAllFiles(_: Any?) {
        collapsedFiles = Set(files.map(\.id))
        rebuild(keepingPlace: false)
        canvas.scroll(to: 0)
        blockViews.update()
    }

    /// The file at the very top of the view stays where it is, so a diff scrolled to its top stays
    /// there. The current file can be the one below it, since that's measured below the header
    /// stuck at the top.
    @objc func expandAllFiles(_: Any?) {
        let top = canvas.content.flatMap { content in
            content.layout.block(atY: canvas.visibleRect.minY).map { files[content.document.blocks[$0].file].id }
        }
        collapsedFiles = []
        if let top {
            rebuildKeepingHeader(of: top)
        } else {
            rebuild(keepingPlace: true)
        }
    }

    @objc func goToNextFile(_: Any?) {
        goToFile(offset: 1)
    }

    @objc func goToPreviousFile(_: Any?) {
        goToFile(offset: -1)
    }

    /// Marks the next file and moves its header to the top, as far as the diff scrolls. Going back
    /// from partway through a file goes to the top of that file first.
    func goToFile(offset: Int) {
        if let adjacentFiles {
            adjacentFiles.move(offset)
            return
        }
        guard let content = canvas.content, let current = commandTarget?.file else { return }
        let starts = content.document.fileStarts
        var target = current + offset
        if offset < 0, scrollTop(ofFile: current, in: content) < canvas.visibleRect.minY - 0.5 {
            target = current
        }
        guard starts.indices.contains(target) else {
            NSSound.beep()
            return
        }
        canvas.clearSelection()
        markedFile = files[target].id
        canvas.scroll(to: scrollTop(ofFile: target, in: content))
        blockViews.update()
    }

    @objc func toggleIgnoreWhitespace(_: Any?) {
        options.update { $0.ignoresWhitespace.toggle() }
    }

    @objc func showMoreContext(_: Any?) {
        options.update { $0.contextLines = $0.moreContext ?? $0.contextLines }
    }

    @objc func showLessContext(_: Any?) {
        options.update { $0.contextLines = $0.lessContext ?? $0.contextLines }
    }

    @objc func openInEditor(_: Any?) {
        guard let path = currentPath else { return }
        openInEditor(path: path)
    }

    @objc func revealChangedFileInFinder(_: Any?) {
        guard let path = currentPath else { return }
        WorkingTreeFile(path: path, in: workTree).revealInFinder()
    }

    @objc func copyAbsolutePath(_: Any?) {
        guard let path = currentPath else { return }
        WorkingTreeFile(path: path, in: workTree).copyAbsolutePath()
    }

    @objc func copyPathFromRepositoryRoot(_: Any?) {
        guard let path = currentPath else { return }
        WorkingTreeFile(path: path, in: workTree).copyPathFromRepositoryRoot()
    }

    @objc func openFileInNewWindow(_: Any?) {
        guard let id = currentFile?.id else { return }
        openFileWindow(id)
    }
}

extension DiffViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleIgnoreWhitespace(_:)):
            menuItem.state = options.options.ignoresWhitespace ? .on : .off
            return true
        case #selector(showMoreContext(_:)):
            return options.options.moreContext != nil
        case #selector(showLessContext(_:)):
            return options.options.lessContext != nil
        case #selector(collapseAllFiles(_:)):
            return allowsCollapsing && files.contains { !collapsedFiles.contains($0.id) }
        case #selector(expandAllFiles(_:)):
            return allowsCollapsing && files.contains { collapsedFiles.contains($0.id) }
        case #selector(goToNextFile(_:)):
            return adjacentFiles?.canGo(1) ?? (files.count > 1)
        case #selector(goToPreviousFile(_:)):
            return adjacentFiles?.canGo(-1) ?? (files.count > 1)
        default:
            return validateFileCommand(menuItem.action)
        }
    }

    private func validateFileCommand(_ action: Selector?) -> Bool {
        guard let file = currentFile else { return false }
        switch action {
        case #selector(collapseFile(_:)): return allowsCollapsing && !collapsedFiles.contains(file.id)
        case #selector(expandFile(_:)): return allowsCollapsing && collapsedFiles.contains(file.id)
        case #selector(openInEditor(_:)), #selector(revealChangedFileInFinder(_:)): return isInWorkingTree(file.changed.path)
        case #selector(openFileInNewWindow(_:)): return opensFileWindows
        default: return true
        }
    }
}
