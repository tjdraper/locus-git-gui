import AppKit

/// The Branch, Commit and Stash menus' commands that act straight away or ask in a sheet, rather
/// than asking in the palette first. Commit commands act on the commit selected in the history.
final class OperationMenuCommands: NSObject {
    static let actions: Set<Selector> = [
        #selector(newBranch(_:)),
        #selector(unsetUpstream(_:)),
        #selector(newTag(_:)),
        #selector(continueOperation(_:)),
        #selector(skipCommit(_:)),
        #selector(abortOperation(_:)),
        #selector(checkOutCommit(_:)),
        #selector(newBranchFromCommit(_:)),
        #selector(newTagOnCommit(_:)),
        #selector(cherryPickCommit(_:)),
        #selector(revertCommit(_:)),
        #selector(softResetToCommit(_:)),
        #selector(mixedResetToCommit(_:)),
        #selector(hardResetToCommit(_:)),
        #selector(rewordCommit(_:)),
        #selector(editCommit(_:)),
        #selector(stashChanges(_:)),
        #selector(stashIncludingUntracked(_:)),
    ]

    /// The ones the repository's other windows pass on to it, such as Continue from the working
    /// area's own window. The rest act on the repository window's selection.
    static let repositoryActions: Set<Selector> = [
        #selector(continueOperation(_:)),
        #selector(skipCommit(_:)),
        #selector(abortOperation(_:)),
        #selector(stashChanges(_:)),
        #selector(stashIncludingUntracked(_:)),
        #selector(newBranch(_:)),
    ]

    private unowned let operations: RepositoryOperationsCoordinator

    init(operations: RepositoryOperationsCoordinator) {
        self.operations = operations
    }

    private var context: OperationContext {
        operations.context
    }

    private var window: NSWindow? {
        operations.actingWindow
    }

    @objc func newBranch(_: Any?) {
        guard let head = context.head?.commit else { return }
        let start = context.checkedOutBranch.map { "“\($0)”" } ?? "HEAD (\(head.prefix(7)))"
        operations.branches.newBranch(at: "HEAD", startTitle: start, from: window)
    }

    /// The branch selected in the sidebar, or the checked-out one.
    @objc func unsetUpstream(_: Any?) {
        guard let branch = upstreamBranch else { return }
        operations.branches.unsetUpstream(of: branch.name, from: window)
    }

    @objc func newTag(_: Any?) {
        guard let head = context.head?.commit else { return }
        let tip = context.checkedOutBranch.map { "the tip of “\($0)”, \(head.prefix(7))" } ?? String(head.prefix(7))
        operations.tags.newTag(at: head, startTitle: tip, from: window)
    }

    @objc func continueOperation(_: Any?) {
        operations.stopped.continueOperation(from: window)
    }

    @objc func skipCommit(_: Any?) {
        operations.stopped.skip(from: window)
    }

    @objc func abortOperation(_: Any?) {
        operations.stopped.abort(from: window)
    }

    @objc func checkOutCommit(_: Any?) {
        guard let commit = operations.selectedCommit() else { return }
        operations.branches.checkOutDetached(commit.hash, named: String(commit.hash.prefix(7)), from: window)
    }

    @objc func newBranchFromCommit(_: Any?) {
        guard let commit = operations.selectedCommit() else { return }
        operations.branches.newBranch(at: commit.hash, startTitle: CommitOperationWorkflow.describe(commit), from: window)
    }

    @objc func newTagOnCommit(_: Any?) {
        guard let commit = operations.selectedCommit() else { return }
        operations.tags.newTag(at: commit.hash, startTitle: CommitOperationWorkflow.describe(commit), from: window)
    }

    @objc func cherryPickCommit(_: Any?) {
        guard let commit = operations.selectedCommit() else { return }
        operations.commits.cherryPick(commit, from: window)
    }

    @objc func revertCommit(_: Any?) {
        guard let commit = operations.selectedCommit() else { return }
        operations.commits.revert(commit, from: window)
    }

    @objc func softResetToCommit(_: Any?) {
        reset(.soft)
    }

    @objc func mixedResetToCommit(_: Any?) {
        reset(.mixed)
    }

    @objc func hardResetToCommit(_: Any?) {
        reset(.hard)
    }

    @objc func rewordCommit(_: Any?) {
        guard let commit = operations.selectedCommit() else { return }
        operations.commits.reword(commit, from: window)
    }

    @objc func editCommit(_: Any?) {
        guard let commit = operations.selectedCommit() else { return }
        operations.commits.edit(commit, from: window)
    }

    @objc func stashChanges(_: Any?) {
        operations.stashes.stash(includingUntracked: false, from: window)
    }

    @objc func stashIncludingUntracked(_: Any?) {
        operations.stashes.stash(includingUntracked: true, from: window)
    }

    private func reset(_ mode: HistoryOperationCommand.ResetMode) {
        guard let commit = operations.selectedCommit() else { return }
        operations.commits.reset(to: commit, mode: mode, from: window)
    }

    private var upstreamBranch: SidebarContents.Branch? {
        if let selection = operations.sidebarSelection(), let branch = context.branch(selection) {
            return branch
        }
        return context.contents?.branches.first(where: \.isCheckedOut)
    }
}

extension OperationMenuCommands: NSMenuItemValidation {
    /// Titled for what they act on, such as “Cherry-Pick onto “main””, and a commit command that
    /// can't act on the selected commit says why in its tooltip.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.toolTip = nil
        switch menuItem.action {
        case #selector(newBranch(_:)), #selector(newTag(_:)):
            return context.head?.commit != nil
        case #selector(unsetUpstream(_:)):
            let branch = upstreamBranch
            menuItem.title = branch.map { "Unset Upstream of “\($0.name)”" } ?? AppCommand.unsetUpstream.title
            return branch?.upstream != nil
        case #selector(continueOperation(_:)), #selector(abortOperation(_:)), #selector(skipCommit(_:)):
            return validateStopped(menuItem)
        case #selector(stashChanges(_:)), #selector(stashIncludingUntracked(_:)):
            return context.hasChanges
        default:
            return validateCommitCommand(menuItem)
        }
    }

    /// The commands for the commit selected in the history.
    private func validateCommitCommand(_ menuItem: NSMenuItem) -> Bool {
        let commit = operations.selectedCommit()
        let branch = context.checkedOutBranch
        let isHead = commit != nil && commit?.hash == context.head?.commit
        switch menuItem.action {
        case #selector(checkOutCommit(_:)), #selector(newBranchFromCommit(_:)), #selector(newTagOnCommit(_:)), #selector(revertCommit(_:)):
            return commit != nil
        case #selector(cherryPickCommit(_:)):
            menuItem.title = branch.map { "Cherry-Pick onto “\($0)”" } ?? AppCommand.cherryPickCommit.title
            return commit != nil && !isHead
        case #selector(softResetToCommit(_:)), #selector(mixedResetToCommit(_:)), #selector(hardResetToCommit(_:)):
            if let command = AppCommand(menuItem: menuItem), let branch {
                menuItem.title = command.title.replacingOccurrences(of: "Reset to", with: "Reset “\(branch)” to")
            }
            return commit != nil && !isHead
        case #selector(rewordCommit(_:)), #selector(editCommit(_:)):
            guard let commit else { return false }
            let problem = operations.commits.rewriteProblem(commit, isInCheckedOutHistory: operations.historyShowsCheckedOutBranch())
            menuItem.toolTip = problem
            return problem == nil
        default:
            return true
        }
    }

    private func validateStopped(_ menuItem: NSMenuItem) -> Bool {
        guard let stopped = operations.stopped.stopped else {
            if let command = AppCommand(menuItem: menuItem) {
                menuItem.title = command.title
            }
            return false
        }
        let name = stopped.kind.title
        switch menuItem.action {
        case #selector(continueOperation(_:)):
            menuItem.title = "Continue \(name)"
            return true
        case #selector(abortOperation(_:)):
            menuItem.title = "Abort \(name)…"
            return true
        default:
            return stopped.kind != .merge
        }
    }
}
