nonisolated enum SidebarSection: String, Codable, CaseIterable, Sendable {
    /// Shown only while something is pinned.
    case pinned
    case branches
    case remotes
    case tags
    case stashes

    var title: String {
        switch self {
        case .pinned: "Pinned"
        case .branches: "Branches"
        case .remotes: "Remotes"
        case .tags: "Tags"
        case .stashes: "Stashes"
        }
    }
}
