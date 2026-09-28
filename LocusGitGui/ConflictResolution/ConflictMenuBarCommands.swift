import AppKit

/// The conflict commands in the File, View and Commit menus, and the file commands every window
/// with changes has.
extension ConflictWindowController: NSMenuItemValidation {
    private var isEditing: Bool {
        editor.state.mode == .editing
    }

    private var isChoosing: Bool {
        if case .choosing = editor.state.mode { true } else { false }
    }

    @objc func saveConflictResolution(_: Any?) {
        save()
    }

    @objc func goToPreviousConflict(_: Any?) {
        editor.state.goToConflict?(-1)
    }

    @objc func goToNextConflict(_: Any?) {
        editor.state.goToConflict?(1)
    }

    @objc func takeOurs(_: Any?) {
        if isChoosing {
            chooseVersion(ofOurs: true)
        } else {
            editor.state.take?(.ours)
        }
    }

    @objc func takeTheirs(_: Any?) {
        if isChoosing {
            chooseVersion(ofOurs: false)
        } else {
            editor.state.take?(.theirs)
        }
    }

    @objc func takeBoth(_: Any?) {
        editor.state.take?(.oursThenTheirs)
    }

    @objc func markConflictResolved(_: Any?) {
        markResolved()
    }

    @objc func toggleConflictBase(_: Any?) {
        editor.setBaseShown(!editor.state.showsBase)
        onChange?()
    }

    @objc func goToNextFile(_: Any?) {
        moveInList(by: 1)
    }

    @objc func goToPreviousFile(_: Any?) {
        moveInList(by: -1)
    }

    private func moveInList(by offset: Int) {
        let paths = list.entries.map(\.path)
        let index = list.selection.flatMap { paths.firstIndex(of: $0) }.map { $0 + offset } ?? 0
        guard paths.indices.contains(index) else {
            NSSound.beep()
            return
        }
        list.selection = paths[index]
    }

    private var shownFile: WorkingTreeFile? {
        list.selection.map { WorkingTreeFile(path: $0, in: commands.repository.workTree) }
    }

    /// Saved first, so the editor opens what the window shows.
    @objc func openInEditor(_: Any?) {
        save()
        shownFile?.openInEditor()
    }

    @objc func revealChangedFileInFinder(_: Any?) {
        shownFile?.revealInFinder()
    }

    @objc func copyAbsolutePath(_: Any?) {
        shownFile?.copyAbsolutePath()
    }

    @objc func copyPathFromRepositoryRoot(_: Any?) {
        shownFile?.copyPathFromRepositoryRoot()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let isEnabled = validateConflictCommand(menuItem) {
            return isEnabled
        }
        switch menuItem.action {
        case #selector(goToNextFile(_:)), #selector(goToPreviousFile(_:)):
            return list.entries.count > 1
        case #selector(openInEditor(_:)), #selector(revealChangedFileInFinder(_:)):
            return shownFile?.exists == true
        case #selector(copyAbsolutePath(_:)), #selector(copyPathFromRepositoryRoot(_:)):
            return shownFile != nil
        default:
            return true
        }
    }

    /// Taking a side is named for the side, once a file shows what the sides are.
    private func validateConflictCommand(_ menuItem: NSMenuItem) -> Bool? {
        let state = editor.state
        let hasCurrent = isEditing && state.current != nil
        switch menuItem.action {
        case #selector(saveConflictResolution(_:)):
            return isEditing && state.isEdited
        case #selector(goToPreviousConflict(_:)), #selector(goToNextConflict(_:)):
            return isEditing && state.conflictCount > 0
        case #selector(takeOurs(_:)):
            menuItem.title = isEditing || isChoosing ? state.takeOursTitle : AppCommand.takeOurs.title
            return isChoosing || hasCurrent
        case #selector(takeTheirs(_:)):
            menuItem.title = isEditing || isChoosing ? state.takeTheirsTitle : AppCommand.takeTheirs.title
            return isChoosing || hasCurrent
        case #selector(takeBoth(_:)):
            return hasCurrent
        case #selector(markConflictResolved(_:)):
            return isEditing
        case #selector(toggleConflictBase(_:)):
            menuItem.state = state.showsBase ? .on : .off
            return isEditing && state.hasBase
        default:
            return nil
        }
    }
}
