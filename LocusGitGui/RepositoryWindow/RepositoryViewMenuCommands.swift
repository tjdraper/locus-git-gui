import AppKit

/// View menu commands, which reach the window through the responder chain from anywhere in it.
extension RepositoryWindowController {
    /// Reached through the responder chain from View > Show Activity.
    @objc func showActivity(_: Any?) {
        openedWindows.showActivity()
    }

    /// Reached through the responder chain from View > Show Notices.
    @objc func showNotices(_: Any?) {
        openedWindows.showNotices()
    }

    /// Reached through the responder chain from View > Filter Sidebar.
    @objc func filterSidebar(_: Any?) {
        columns.showSidebar()
        sidebar.requestFilterFocus()
    }
    /// Reached through the responder chain from View > Go to Uncommitted Changes, from anywhere in
    /// the window. From another branch's history it goes back to the checked-out branch's, where the
    /// working area is. The subject takes focus, since writing the message is usually what's next.
    @objc func goToUncommittedChanges(_: Any?) {
        if commitColumns.history.workingArea == nil {
            sidebar.selection = nil
        }
        guard commitColumns.history.workingArea != nil else {
            NSSound.beep()
            return
        }
        commitColumns.history.selectWorkingArea()
        commitColumns.workingArea.focusSubject()
    }

    /// Reached through the responder chain from View > Open Uncommitted Changes in New Window, and
    /// passed on by the windows opened from this one, so it opens whatever the history shows.
    @objc func openUncommittedChangesWindow(_: Any?) {
        openWorkingAreaWindow()
    }

    /// Commands the repository's other windows pass on to `repositoryTarget(for:)`.
    static let repositoryActions: Set<Selector> = Set([
        #selector(openUncommittedChangesWindow(_:)), #selector(showActivity(_:)), #selector(showNotices(_:)),
    ])
        .union(RemoteSyncWorkflow.actions)
        .union(RemoteEditingWorkflow.actions)
        .union(OperationMenuCommands.repositoryActions)
        .union([#selector(MessageFormatStore.toggleMessageMarkdown(_:))])
        .union(ConflictWindowCommand.actions)

    func repositoryTarget(for action: Selector) -> Any {
        remotes.target(forAction: action) ?? operations.target(forAction: action) ?? messageFormat.target(forAction: action)
            ?? openedWindows.target(forAction: action) ?? self
    }
}
