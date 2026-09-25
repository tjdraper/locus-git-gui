/// What a sidebar row stands for, which is also what the window remembers as the sidebar's
/// selection.
nonisolated enum SidebarItemID: Hashable, Codable, Sendable {
    /// A branch, remote branch or tag, by its full name, such as `refs/heads/main`.
    case ref(String)
    case remote(String)
    /// By the stash's commit, which stays the same while newer stashes renumber it.
    case stash(String)
}
