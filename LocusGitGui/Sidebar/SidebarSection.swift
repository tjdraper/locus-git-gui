nonisolated enum SidebarSection: String, Codable, CaseIterable, Sendable {
    case branches
    case remotes
    case tags
    case stashes

    var title: String {
        switch self {
        case .branches: "Branches"
        case .remotes: "Remotes"
        case .tags: "Tags"
        case .stashes: "Stashes"
        }
    }
}
