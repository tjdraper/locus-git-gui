import AppKit

/// The branch, tag and stash commands in a sidebar row's context menu, titled for that row.
enum OperationSidebarMenu {
    static func items(for id: SidebarItemID, in operations: RepositoryOperationsCoordinator) -> [[SidebarMenuItem]] {
        let context = operations.context
        if let branch = context.branch(id) {
            return branchItems(branch, operations)
        }
        if let (remote, branch) = context.remoteBranch(id) {
            return remoteBranchItems(id, name: "\(remote)/\(branch.name)", operations)
        }
        if let tag = context.tag(id) {
            return tagItems(tag.name, operations)
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
        var groups: [[SidebarMenuItem]] = [[
            SidebarMenuItem(title: "Check Out", isEnabled: !branch.isCheckedOut) { operations.branches.checkOut(name, from: window()) },
            newBranch(from: name, operations),
            newTag(on: "refs/heads/\(name)", named: "the tip of “\(name)”", operations),
        ]]
        if let current = operations.context.checkedOutBranch, !branch.isCheckedOut {
            groups.append(mergeAndRebase(name, into: current, operations))
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
        name: String,
        _ operations: RepositoryOperationsCoordinator
    ) -> [[SidebarMenuItem]] {
        var groups: [[SidebarMenuItem]] = [[
            SidebarMenuItem(title: "Check Out") { operations.branches.checkOut(remoteBranch: id, from: operations.actingWindow) },
            newBranch(from: name, operations),
            newTag(on: "refs/remotes/\(name)", named: "the tip of “\(name)”", operations),
        ]]
        if let current = operations.context.checkedOutBranch {
            groups.append(mergeAndRebase(name, into: current, operations))
        }
        return groups
    }

    private static func tagItems(_ tag: String, _ operations: RepositoryOperationsCoordinator) -> [[SidebarMenuItem]] {
        let window = { operations.actingWindow }
        var groups: [[SidebarMenuItem]] = [[
            SidebarMenuItem(title: "Check Out") {
                operations.branches.checkOutDetached("refs/tags/\(tag)", named: "the tag “\(tag)”", from: window())
            },
            newBranch(from: tag, operations),
        ]]
        if let current = operations.context.checkedOutBranch {
            groups.append([SidebarMenuItem(title: "Merge “\(tag)” into “\(current)”") { operations.merging.merge(tag, from: window()) }])
        }
        groups.append([SidebarMenuItem(title: "Delete Tag…") { operations.tags.delete(tag, from: window()) }])
        return groups
    }

    private static func newBranch(from start: String, _ operations: RepositoryOperationsCoordinator) -> SidebarMenuItem {
        SidebarMenuItem(title: "New Branch from Here…") {
            operations.branches.newBranch(at: start, startTitle: "“\(start)”", from: operations.actingWindow)
        }
    }

    private static func newTag(on revision: String, named title: String, _ operations: RepositoryOperationsCoordinator) -> SidebarMenuItem {
        SidebarMenuItem(title: "New Tag Here…") {
            operations.tags.newTag(at: revision, startTitle: title, from: operations.actingWindow)
        }
    }

    private static func mergeAndRebase(
        _ name: String,
        into current: String,
        _ operations: RepositoryOperationsCoordinator
    ) -> [SidebarMenuItem] {
        let window = { operations.actingWindow }
        return [
            SidebarMenuItem(title: "Merge “\(name)” into “\(current)”") { operations.merging.merge(name, from: window()) },
            SidebarMenuItem(title: "Rebase “\(current)” onto “\(name)”") { operations.merging.rebase(onto: name, from: window()) },
        ]
    }
}

/// The commands in a commit's context menu in the history, which act on that commit whether or not
/// it's the one selected.
enum OperationHistoryMenu {
    static func items(for commit: Commit, in operations: RepositoryOperationsCoordinator) -> [[NSMenuItem]] {
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
        if let current, !isHead {
            groups.append([
                ActionMenuItem.make(title: "Merge into “\(current)”") { operations.merging.merge(commit.hash, from: window()) },
                ActionMenuItem.make(title: "Rebase “\(current)” onto Here") {
                    operations.merging.rebase(onto: commit.hash, from: window())
                },
            ])
        }
        groups.append(resetItems(commit, isHead: isHead, operations))
        let problem = operations.commits.rewriteProblem(commit, isInCheckedOutHistory: operations.historyShowsCheckedOutBranch())
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
