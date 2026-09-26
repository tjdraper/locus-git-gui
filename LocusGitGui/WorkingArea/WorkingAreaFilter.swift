/// Which of the working area's changes are shown: all of them, only what's staged, or only what
/// isn't yet, which takes in untracked files and conflicts.
nonisolated enum WorkingAreaFilter: Int, CaseIterable, Sendable {
    case all
    case staged
    case unstaged

    var title: String {
        switch self {
        case .all: "All"
        case .staged: "Staged"
        case .unstaged: "Unstaged"
        }
    }

    func includes(_ group: WorkingAreaGroup) -> Bool {
        switch self {
        case .all: true
        case .staged: group == .staged
        case .unstaged: group != .staged
        }
    }

    /// When there are changes, but none of the ones shown.
    var noneShown: String {
        switch self {
        case .all: "No uncommitted changes."
        case .staged: "Nothing is staged."
        case .unstaged: "Everything is staged."
        }
    }
}
