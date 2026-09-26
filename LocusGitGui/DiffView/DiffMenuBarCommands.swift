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

    private var currentPath: String? {
        commandTarget?.file.map { files[$0].changed.path }
    }

    @objc func collapseFile(_: Any?) {
        guard let path = currentPath, !collapsedPaths.contains(path) else { return }
        toggleCollapsed(path)
    }

    @objc func expandFile(_: Any?) {
        guard let path = currentPath, collapsedPaths.contains(path) else { return }
        toggleCollapsed(path)
    }

    @objc func collapseAllFiles(_: Any?) {
        collapsedPaths = Set(files.map(\.changed.path))
        rebuild(keepingPlace: false)
        canvas.scroll(to: 0)
        blockViews.update()
    }

    /// The file at the very top of the view stays where it is, so a diff scrolled to its top stays
    /// there. The current file can be the one below it, since that's measured below the header
    /// stuck at the top.
    @objc func expandAllFiles(_: Any?) {
        let top = canvas.content.flatMap { content in
            content.layout.block(atY: canvas.visibleRect.minY).map { files[content.document.blocks[$0].file].changed.path }
        }
        collapsedPaths = []
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

    /// Moves the next file's header to the top. Going back from partway through a file goes to the
    /// top of that file first.
    private func goToFile(offset: Int) {
        if let adjacentFiles {
            adjacentFiles.move(offset)
            return
        }
        guard let content = canvas.content, let current = commandTarget?.file else { return }
        let starts = content.document.fileStarts
        var target = current + offset
        if offset < 0, content.layout.top(of: starts[current]) < canvas.visibleRect.minY - 0.5 {
            target = current
        }
        guard starts.indices.contains(target) else {
            NSSound.beep()
            return
        }
        canvas.clearSelection()
        canvas.scroll(to: content.layout.top(of: starts[target]))
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
        guard let path = currentPath else { return }
        openFileWindow(path: path)
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
            return files.contains { !collapsedPaths.contains($0.changed.path) }
        case #selector(expandAllFiles(_:)):
            return files.contains { collapsedPaths.contains($0.changed.path) }
        case #selector(goToNextFile(_:)):
            return adjacentFiles?.canGo(1) ?? (files.count > 1)
        case #selector(goToPreviousFile(_:)):
            return adjacentFiles?.canGo(-1) ?? (files.count > 1)
        default:
            return validateFileCommand(menuItem.action)
        }
    }

    private func validateFileCommand(_ action: Selector?) -> Bool {
        guard let path = currentPath else { return false }
        switch action {
        case #selector(collapseFile(_:)): return !collapsedPaths.contains(path)
        case #selector(expandFile(_:)): return collapsedPaths.contains(path)
        case #selector(openInEditor(_:)), #selector(revealChangedFileInFinder(_:)): return isInWorkingTree(path)
        case #selector(openFileInNewWindow(_:)): return opensFileWindows
        default: return true
        }
    }
}
