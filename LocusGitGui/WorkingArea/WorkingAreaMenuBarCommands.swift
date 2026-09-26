import AppKit

/// The menu bar's commit and staging commands. File and hunk commands act on the current file and
/// hunk in the diff: the ones with the selection in them, or at the top of the view. The window
/// passes them on from whichever column has focus.
extension WorkingAreaViewController {
    static let windowActions: Set<Selector> = [
        #selector(commitChanges(_:)),
        #selector(toggleAmend(_:)),
        #selector(toggleFileStaging(_:)),
        #selector(toggleHunkStaging(_:)),
        #selector(discardFile(_:)),
        #selector(discardHunk(_:)),
        #selector(stageAll(_:)),
        #selector(unstageAll(_:)),
        #selector(showAllChanges(_:)),
        #selector(showStagedChanges(_:)),
        #selector(showUnstagedChanges(_:)),
    ]

    private var isShowing: Bool {
        isViewLoaded && !view.isHiddenOrHasHiddenAncestor
    }

    private var currentFile: DiffFile? {
        isShowing ? diff.currentFile : nil
    }

    /// A hunk, and its changed lines the selection picks, if any.
    private struct CurrentHunk {
        let file: DiffFile
        let hunk: Int
        let lines: [Int]
    }

    private var currentHunk: CurrentHunk? {
        guard isShowing, let target = diff.commandTarget?.hunk else { return nil }
        let file = diff.files[target.file]
        let lines = diff.selectedLines(inFile: target.file, hunk: target.hunk)
            .filter { file.patch.hunks[target.hunk].lines[$0].kind != .context }
        return CurrentHunk(file: file, hunk: target.hunk, lines: lines)
    }

    @objc func showAllChanges(_: Any?) {
        setFilter(.all)
    }

    @objc func showStagedChanges(_: Any?) {
        setFilter(.staged)
    }

    @objc func showUnstagedChanges(_: Any?) {
        setFilter(.unstaged)
    }

    @objc func commitChanges(_: Any?) {
        editor.commit?()
    }

    @objc func toggleAmend(_: Any?) {
        editor.toggleAmend?()
    }

    /// A conflicted file is staged to mark it resolved.
    @objc func toggleFileStaging(_: Any?) {
        guard let file = currentFile else {
            NSSound.beep()
            return
        }
        if WorkingAreaGroup(file) == .staged {
            staging.unstage([file])
        } else {
            staging.stage([file])
        }
    }

    @objc func toggleHunkStaging(_: Any?) {
        guard let current = currentHunk, let group = WorkingAreaGroup(current.file), group != .conflicted else {
            NSSound.beep()
            return
        }
        staging.apply(group == .staged ? .unstage : .stage, lines: current.lines, hunk: current.hunk, of: current.file)
    }

    @objc func discardFile(_: Any?) {
        guard let file = currentFile, WorkingAreaGroup(file) == .unstaged || WorkingAreaGroup(file) == .untracked else {
            NSSound.beep()
            return
        }
        staging.discard(file)
    }

    @objc func discardHunk(_: Any?) {
        guard let current = currentHunk, [.unstaged, .untracked].contains(WorkingAreaGroup(current.file)) else {
            NSSound.beep()
            return
        }
        staging.apply(.discard, lines: current.lines, hunk: current.hunk, of: current.file)
    }

    /// Every unstaged change and untracked file. Conflicts stay as they are, since staging one marks
    /// it resolved, which is for the user to say.
    @objc func stageAll(_: Any?) {
        staging.stageAll(excluding: files(in: [.conflicted]))
    }

    @objc func unstageAll(_: Any?) {
        staging.unstageAll()
    }
}

extension WorkingAreaViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(commitChanges(_:)):
            menuItem.title = editor.commitTitle
            return isShowing && editor.canCommit
        case #selector(toggleAmend(_:)):
            menuItem.state = editor.isAmending ? .on : .off
            return isShowing && !editor.isCommitting && (editor.canAmend || editor.isAmending)
        case #selector(showAllChanges(_:)), #selector(showStagedChanges(_:)), #selector(showUnstagedChanges(_:)):
            let filter: WorkingAreaFilter = switch menuItem.action {
            case #selector(showStagedChanges(_:)): .staged
            case #selector(showUnstagedChanges(_:)): .unstaged
            default: .all
            }
            menuItem.state = filter == self.filter ? .on : .off
            return isShowing
        case #selector(stageAll(_:)):
            let summary = status.map(WorkingAreaSummary.init)
            return (summary?.unstaged ?? 0) + (summary?.untracked ?? 0) > 0
        case #selector(unstageAll(_:)):
            return (status.map(WorkingAreaSummary.init)?.staged ?? 0) > 0
        default:
            return validateStagingCommand(menuItem)
        }
    }

    /// The commands that act on the current file or hunk.
    private func validateStagingCommand(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleFileStaging(_:)):
            menuItem.title = switch currentFile.flatMap(WorkingAreaGroup.init) {
            case .conflicted: "Mark as Resolved"
            case .staged: "Unstage File"
            default: AppCommand.toggleFileStaging.title
            }
            return currentFile != nil
        case #selector(toggleHunkStaging(_:)):
            return validateHunkCommand(menuItem, verb: nil)
        case #selector(discardFile(_:)):
            let group = currentFile.flatMap(WorkingAreaGroup.init)
            menuItem.title = group == .untracked ? "Move to Trash…" : AppCommand.discardFile.title
            return group == .unstaged || group == .untracked
        case #selector(discardHunk(_:)):
            return validateHunkCommand(menuItem, verb: "Discard")
        default:
            return true
        }
    }

    /// Titled for lines when some are picked. `verb` is nil for staging, which is Stage or Unstage
    /// by the file's group.
    private func validateHunkCommand(_ menuItem: NSMenuItem, verb: String?) -> Bool {
        let hunk = currentHunk
        let group = hunk.flatMap { WorkingAreaGroup($0.file) }
        let noun = hunk?.lines.isEmpty == false ? "Lines" : "Hunk"
        if let verb {
            menuItem.title = "\(verb) \(noun)…"
            return staging.canActOnHunks && (group == .unstaged || group == .untracked)
        }
        menuItem.title = "\(group == .staged ? "Unstage" : "Stage") \(noun)"
        return staging.canActOnHunks && group != nil && group != .conflicted
    }
}
