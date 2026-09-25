/// What the window's title bar says about the repository: the branch and its state as the
/// subtitle, and the dot in the close button whenever it isn't clean.
nonisolated struct RepositoryTitleBar: Equatable {
    let subtitle: String
    /// The dot is information, not a warning: everything it covers is already on disk.
    let isEdited: Bool

    /// Shown while the latest refresh failed, so the title bar never repeats a state that may no
    /// longer be true. Without a status, whether anything changed is unknown, so there is no dot.
    static let unavailable = RepositoryTitleBar(subtitle: "Status unavailable", isEdited: false)

    private init(subtitle: String, isEdited: Bool) {
        self.subtitle = subtitle
        self.isEdited = isEdited
    }

    init(status: RepositoryStatus, operation: InProgressOperation?) {
        let files = status.files.filter { $0.state != .ignored }
        isEdited = !files.isEmpty || operation != nil
        let state = operation.map(Self.describe) ?? Self.describe(files)
        subtitle = "\(Self.branch(status.branch, operation: operation)) · \(state)"
    }

    /// A rebase detaches HEAD while it runs, but the branch it is rebasing is the one that matters.
    private static func branch(_ branch: RepositoryStatus.Branch, operation: InProgressOperation?) -> String {
        if let name = branch.name {
            return name
        }
        if case let .rebasing(name?, _, _) = operation {
            return name
        }
        if let commit = branch.commit {
            return "Detached HEAD at \(commit.prefix(7))"
        }
        return "Detached HEAD"
    }

    private static func describe(_ operation: InProgressOperation) -> String {
        switch operation {
        case let .rebasing(_, step?, total?):
            "Rebasing \(step) of \(total)"
        case .rebasing:
            "Rebasing"
        case .merging:
            "Merging"
        case .cherryPicking:
            "Cherry-picking"
        case .reverting:
            "Reverting"
        case .bisecting:
            "Bisecting"
        }
    }

    private static func describe(_ files: [RepositoryStatus.File]) -> String {
        let hasStaged = files.contains { file in
            if case .changed(staged: .some, unstaged: _) = file.state { true } else { false }
        }
        let hasUnstaged = files.contains { file in
            switch file.state {
            case .changed(staged: _, unstaged: .some), .untracked, .conflicted:
                true
            case .changed, .ignored:
                false
            }
        }
        switch (hasStaged, hasUnstaged) {
        case (true, true):
            return "Staged and unstaged changes"
        case (true, false):
            return "Staged changes"
        case (false, true):
            return "Uncommitted changes"
        case (false, false):
            return "Clean"
        }
    }
}
