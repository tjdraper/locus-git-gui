/// The groups the working area lists its files in, in the order they're shown. A file with staged
/// and unstaged changes is in both. Staged changes come last, so staging a file or some of its lines
/// doesn't move the files still to be staged. The raw values are saved with where the working area
/// was left, so they stay as they are whatever the order.
nonisolated enum WorkingAreaGroup: Int, CaseIterable, Sendable {
    /// Stopped on by a merge, rebase or cherry-pick, and not yet resolved.
    case conflicted = 0
    case unstaged = 2
    case untracked = 3
    case staged = 1

    var title: String {
        switch self {
        case .conflicted: "Conflicts"
        case .staged: "Staged Changes"
        case .unstaged: "Unstaged Changes"
        case .untracked: "Untracked Files"
        }
    }

    /// Nil for a file in a diff that isn't the working area's.
    init?(_ file: DiffFile) {
        guard let group = file.group.flatMap(WorkingAreaGroup.init(rawValue:)) else { return nil }
        self = group
    }
}
