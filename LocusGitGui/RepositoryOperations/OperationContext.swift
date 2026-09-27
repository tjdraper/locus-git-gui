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

    /// A branch, remote branch or tag, named as the user knows it, such as `origin/main`, and as
    /// Git is given it. Git is given the short name, which its merge messages repeat, unless that's
    /// also another ref's, since Git would then pick a tag over a branch and a branch over a remote
    /// branch, or unless it starts with a hyphen, which a tag fetched from a remote can, and which
    /// Git would read as an option.
    func revision(_ id: SidebarItemID) -> Revision? {
        guard case let .ref(fullName) = id, contents?.contains(id) == true, let name = Self.shortName(fullName) else { return nil }
        let isAmbiguous = name.hasPrefix("-") || refs.contains { $0.name != fullName && Self.shortName($0.name) == name }
        return Revision(argument: isAmbiguous ? fullName : name, name: name)
    }

    private static func shortName(_ fullName: String) -> String? {
        for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] where fullName.hasPrefix(prefix) {
            return String(fullName.dropFirst(prefix.count))
        }
        return nil
    }
}

/// What a command acts on: `argument` as Git is given it, and `name` as the user knows it.
struct Revision {
    let argument: String
    let name: String

    /// Named by its short hash.
    static func commit(_ hash: String) -> Revision {
        Revision(argument: hash, name: String(hash.prefix(7)))
    }
}
