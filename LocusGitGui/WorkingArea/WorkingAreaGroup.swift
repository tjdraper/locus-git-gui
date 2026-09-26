/// The groups the working area lists its files in, in the order they're shown. A file with staged
/// and unstaged changes is in both.
nonisolated enum WorkingAreaGroup: Int, CaseIterable, Sendable {
    /// Stopped on by a merge, rebase or cherry-pick, and not yet resolved.
    case conflicted
    case staged
    case unstaged
    case untracked

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
