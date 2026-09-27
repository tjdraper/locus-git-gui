/// What the branch, stash, tag and history commands need to know about the repository, as of the
/// last refresh.
struct OperationContext {
    var head: RepositoryStatus.Branch?
    var refs: [Ref] = []
    var contents: SidebarContents?
    var operation: InProgressOperation?
    var conflicts = 0
    /// Anything staged, unstaged or untracked.
    var hasChanges = false
    /// Changes to files Git tracks, which a hard reset throws away. Untracked files it leaves.
    var hasTrackedChanges = false

    /// Nil when HEAD is detached.
    var checkedOutBranch: String? {
        head?.name
    }

    var branchNames: Set<String> {
        Set(contents?.branches.map(\.name) ?? [])
    }

    var tagNames: Set<String> {
        Set(contents?.tags.map(\.name) ?? [])
    }

    func branch(_ id: SidebarItemID) -> SidebarContents.Branch? {
        contents?.branches.first { $0.id == id }
    }

    /// With the remote it's on.
    func remoteBranch(_ id: SidebarItemID) -> (remote: String, branch: SidebarContents.RemoteBranch)? {
        for remote in contents?.remotes ?? [] {
            if let branch = remote.branches.first(where: { $0.id == id }) {
                return (remote.name, branch)
            }
        }
        return nil
    }

    func tag(_ id: SidebarItemID) -> SidebarContents.Tag? {
        contents?.tags.first { $0.id == id }
    }

    func stash(_ id: SidebarItemID) -> SidebarContents.StashEntry? {
        contents?.stashes.first { $0.id == id }
    }

    /// A branch, remote branch or tag as Git names it in a command, such as `origin/main`.
    func revisionName(_ id: SidebarItemID) -> String? {
        if let branch = branch(id) {
            return branch.name
        }
        if let (remote, branch) = remoteBranch(id) {
            return "\(remote)/\(branch.name)"
        }
        return tag(id)?.name
    }
}
