/// What a history window is called: the branch, tag, remote or stash it shows, and what kind of
/// thing that is, which goes in the subtitle after the repository's name.
nonisolated struct HistoryWindowTitle: Equatable, Sendable {
    let name: String
    let kind: String
    /// Said when the repository no longer has it, such as a branch deleted in Terminal.
    let gone: String

    /// Read from the sidebar's contents when they have it, and otherwise worked out from the item
    /// itself, as for a window reopened after its branch was deleted.
    init(_ item: SidebarItemID, in contents: SidebarContents?) {
        switch item {
        case let .ref(name) where name.hasPrefix(Self.remoteBranchPrefix):
            let remote = contents?.remote(containing: item)
            let branch = contents?.remotes.first { $0.name == remote }?.branches.first { $0.id == item }
            self.name = remote.flatMap { remote in branch.map { remote + "/" + $0.name } }
                ?? String(name.dropFirst(Self.remoteBranchPrefix.count))
            kind = "Remote Branch"
            gone = "Deleted"
        case let .ref(name) where name.hasPrefix(Self.tagPrefix):
            self.name = String(name.dropFirst(Self.tagPrefix.count))
            kind = "Tag"
            gone = "Deleted"
        case let .ref(name):
            self.name = name.hasPrefix(Self.branchPrefix) ? String(name.dropFirst(Self.branchPrefix.count)) : name
            kind = "Branch"
            gone = "Deleted"
        case let .remote(name):
            self.name = name
            kind = "Remote"
            gone = "Removed"
        case let .stash(commit):
            name = contents?.stashes.first { $0.id == item }?.message ?? "Stash \(commit.prefix(7))"
            kind = "Stash"
            gone = "Dropped"
        }
    }

    private static let branchPrefix = "refs/heads/"
    private static let remoteBranchPrefix = "refs/remotes/"
    private static let tagPrefix = "refs/tags/"
}
