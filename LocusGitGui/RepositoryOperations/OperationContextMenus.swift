import AppKit

/// The branch, tag and stash commands in a sidebar row's context menu, titled for that row.
enum OperationSidebarMenu {
    static func items(for id: SidebarItemID, in operations: RepositoryOperationsCoordinator) -> [[SidebarMenuItem]] {
        let context = operations.context
        if let branch = context.branch(id) {
            return branchItems(branch, operations)
        }
        if context.remoteBranch(id) != nil, let revision = context.revision(id) {
            return remoteBranchItems(id, revision, operations)
        }
        if let tag = context.tag(id), let revision = context.revision(id) {
            return tagItems(tag.name, revision, operations)
        }
        if case let .stash(commit) = id, context.stash(id) != nil {
            let window = { operations.actingWindow }
            return [[
                SidebarMenuItem(title: "Apply") { operations.stashes.apply(commit, from: window()) },
                SidebarMenuItem(title: "Pop") { operations.stashes.pop(commit, from: window()) },
                SidebarMenuItem(title: "Drop…") { operations.stashes.drop(commit, from: window()) },
            ]]
        }
        return []
    }

    private static func branchItems(
        _ branch: SidebarContents.Branch,
        _ operations: RepositoryOperationsCoordinator
    ) -> [[SidebarMenuItem]] {
        let window = { operations.actingWindow }
        let name = branch.name
        let revision = operations.context.revision(branch.id) ?? Revision(argument: name, name: name)
        var groups: [[SidebarMenuItem]] = [[
            SidebarMenuItem(title: "Check Out", isEnabled: !branch.isCheckedOut) { operations.branches.checkOut(name, from: window()) },
            newBranch(from: revision, operations),
            newTag(on: "refs/heads/\(name)", named: "the tip of “\(name)”", operations),
        ]]
        if let current = operations.context.checkedOutBranch, !branch.isCheckedOut {
            groups.append(mergeAndRebase(revision, into: current, operations))
        }
        groups.append([
            SidebarMenuItem(title: "Rename…") { operations.branches.rename(name, from: window()) },
            SidebarMenuItem(title: "Delete…", isEnabled: !branch.isCheckedOut) { operations.branches.delete(name, from: window()) },
        ])
        var upstream = [SidebarMenuItem(title: "Set Upstream…") {
            operations.selectInSidebar?(branch.id)
            MenuBarCommandReader.perform(.setUpstream)
        }]
        if branch.upstream != nil {
            upstream.append(SidebarMenuItem(title: "Unset Upstream") { operations.branches.unsetUpstream(of: name, from: window()) })
        }
        groups.append(upstream)
        return groups
    }

    private static func remoteBranchItems(
        _ id: SidebarItemID,
        _ revision: Revision,
        _ operations: RepositoryOperationsCoordinator
    ) -> [[SidebarMenuItem]] {
        var groups: [[SidebarMenuItem]] = [[
            SidebarMenuItem(title: "Check Out") { operations.branches.checkOut(remoteBranch: id, from: operations.actingWindow) },
            newBranch(from: revision, operations),
            newTag(on: "refs/remotes/\(revision.name)", named: "the tip of “\(revision.name)”", operations),
        ]]
        if let current = operations.context.checkedOutBranch {
            groups.append(mergeAndRebase(revision, into: current, operations))
        }
        return groups
    }

    private static func tagItems(
        _ tag: String,
        _ revision: Revision,
        _ operations: RepositoryOperationsCoordinator
    ) -> [[SidebarMenuItem]] {
        let window = { operations.actingWindow }
        var groups: [[SidebarMenuItem]] = [[
            SidebarMenuItem(title: "Check Out") {
                operations.branches.checkOutDetached("refs/tags/\(tag)", named: "the tag “\(tag)”", from: window())
            },
            newBranch(from: revision, operations),
        ]]
        if let current = operations.context.checkedOutBranch {
            groups.append([SidebarMenuItem(title: "Merge “\(tag)” into “\(current)”") {
                operations.merging.merge(revision, from: window())
            }])
        }
        groups.append([SidebarMenuItem(title: "Delete Tag…") { operations.tags.delete(tag, from: window()) }])
        return groups
    }

    private static func newBranch(from start: Revision, _ operations: RepositoryOperationsCoordinator) -> SidebarMenuItem {
        SidebarMenuItem(title: "New Branch from Here…") {
            operations.branches.newBranch(at: start.argument, startTitle: "“\(start.name)”", from: operations.actingWindow)
        }
    }

    private static func newTag(on revision: String, named title: String, _ operations: RepositoryOperationsCoordinator) -> SidebarMenuItem {
        SidebarMenuItem(title: "New Tag Here…") {
            operations.tags.newTag(at: revision, startTitle: title, from: operations.actingWindow)
        }
    }

    private static func mergeAndRebase(
        _ revision: Revision,
        into current: String,
        _ operations: RepositoryOperationsCoordinator
    ) -> [SidebarMenuItem] {
        let window = { operations.actingWindow }
        return [
            SidebarMenuItem(title: "Merge “\(revision.name)” into “\(current)”") { operations.merging.merge(revision, from: window()) },
            SidebarMenuItem(title: "Rebase “\(current)” onto “\(revision.name)”") {
                operations.merging.rebase(onto: revision, from: window())
            },
        ]
    }
}

/// The commands in a commit's context menu in the history, which act on that commit whether or not
/// it's the one selected.
enum OperationHistoryMenu {
    /// `isInCheckedOutHistory` when the history the commit was picked in is the checked-out
    /// branch's, which settles whether it can be reworded or edited.
    static func items(for commit: Commit, isInCheckedOutHistory: Bool, in operations: RepositoryOperationsCoordinator) -> [[NSMenuItem]] {
        let context = operations.context
        let window = { operations.actingWindow }
        let current = context.checkedOutBranch
        let isHead = commit.hash == context.head?.commit
        let short = String(commit.hash.prefix(7))
        var groups: [[NSMenuItem]] = [[
            ActionMenuItem.make(title: AppCommand.checkOutCommit.title, isEnabled: !isHead || current != nil) {
                operations.branches.checkOutDetached(commit.hash, named: short, from: window())
            },
            ActionMenuItem.make(title: "New Branch from Here…") {
                operations.branches.newBranch(at: commit.hash, startTitle: CommitOperationWorkflow.describe(commit), from: window())
            },
            ActionMenuItem.make(title: "New Tag Here…") {
                operations.tags.newTag(at: commit.hash, startTitle: CommitOperationWorkflow.describe(commit), from: window())
            },
        ]]
        groups.append([
            ActionMenuItem.make(title: current.map { "Cherry-Pick onto “\($0)”" } ?? AppCommand.cherryPickCommit.title,
                                isEnabled: !isHead) {
                operations.commits.cherryPick(commit, from: window())
            },
            ActionMenuItem.make(title: AppCommand.revertCommit.title) { operations.commits.revert(commit, from: window()) },
        ])
        // Merging a commit already on the branch does nothing, and rebasing onto one flattens the
        // merges after it, so both are only for a commit from elsewhere.
        let isOnBranch = isInCheckedOutHistory || operations.commits.ancestry.isOnCheckedOutBranch(commit.hash) != false
        if let current, !isOnBranch {
            groups.append([
                ActionMenuItem.make(title: "Merge into “\(current)”") { operations.merging.merge(.commit(commit.hash), from: window()) },
                ActionMenuItem.make(title: "Rebase “\(current)” onto Here") {
                    operations.merging.rebase(onto: .commit(commit.hash), from: window())
                },
            ])
        }
        groups.append(resetItems(commit, isHead: isHead, operations))
        let problem = operations.commits.rewriteProblem(commit, isInCheckedOutHistory: isInCheckedOutHistory)
        groups.append([
            ActionMenuItem.make(title: "Reword…", isEnabled: problem == nil, toolTip: problem) {
                operations.commits.reword(commit, from: window())
            },
            ActionMenuItem.make(title: "Edit…", isEnabled: problem == nil, toolTip: problem) {
                operations.commits.edit(commit, from: window())
            },
        ])
        return groups
    }

    private static func resetItems(_ commit: Commit, isHead: Bool, _ operations: RepositoryOperationsCoordinator) -> [NSMenuItem] {
        let branch = operations.context.checkedOutBranch.map { "“\($0)”" } ?? "HEAD"
        return HistoryOperationCommand.ResetMode.allCases.map { mode in
            let title = switch mode {
            case .soft: "Soft Reset \(branch) to Here"
            case .mixed: "Mixed Reset \(branch) to Here"
            case .hard: "Hard Reset \(branch) to Here…"
            }
            return ActionMenuItem.make(title: title, isEnabled: !isHead) {
                operations.commits.reset(to: commit, mode: mode, from: operations.actingWindow)
            }
        }
    }
}
