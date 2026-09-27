/// The Git commands that bring commits from elsewhere onto a branch, undo them, or move the branch:
/// merge, rebase, cherry-pick, revert and reset, and continuing, skipping or aborting one that
/// stopped partway.
nonisolated enum HistoryOperationCommand {
    enum ResetMode: String, Sendable, CaseIterable {
        /// Keeps the changes of the commits left behind, staged.
        case soft
        /// Keeps them as unstaged changes.
        case mixed
        /// Throws them away, along with any uncommitted changes.
        case hard
    }

    /// An operation that stopped partway, on conflicts or at a commit to edit.
    enum Stopped: Sendable {
        case merge
        case rebase
        case cherryPick
        case revert

        var name: String {
            switch self {
            case .merge: "merge"
            case .rebase: "rebase"
            case .cherryPick: "cherry-pick"
            case .revert: "revert"
            }
        }

        /// As a menu item names it, such as Continue Cherry-Pick.
        var title: String {
            switch self {
            case .merge: "Merge"
            case .rebase: "Rebase"
            case .cherryPick: "Cherry-Pick"
            case .revert: "Revert"
            }
        }
    }

    /// The app has no terminal to run an editor in, so Git keeps the message it already has.
    static let keepMessage = ["GIT_EDITOR": "true"]

    /// `autostash` stashes local changes first and puts them back once the merge is done, as Git
    /// does itself.
    static func merge(_ revision: String, autostash: Bool = false) -> GitCommand {
        var command = GitCommand.changing(["merge", "--no-edit"] + (autostash ? ["--autostash"] : []) + [revision])
        command.environment = keepMessage
        return command
    }

    /// Rebases `branch` onto `upstream`, checking `branch` out first when it's given.
    static func rebase(onto upstream: String, branch: String? = nil, autostash: Bool = false) -> GitCommand {
        var command = GitCommand.changing(["rebase"] + (autostash ? ["--autostash"] : []) + [upstream] + (branch.map { [$0] } ?? []))
        command.environment = keepMessage
        return command
    }

    /// A merge commit is picked or reverted against its first parent, the branch it was merged into.
    static func cherryPick(_ commit: String, isMerge: Bool) -> GitCommand {
        var command = GitCommand.changing(["cherry-pick"] + (isMerge ? ["--mainline", "1"] : []) + [commit])
        command.environment = keepMessage
        return command
    }

    static func revert(_ commit: String, isMerge: Bool) -> GitCommand {
        var command = GitCommand.changing(["revert", "--no-edit"] + (isMerge ? ["--mainline", "1"] : []) + [commit])
        command.environment = keepMessage
        return command
    }

    static func reset(to commit: String, mode: ResetMode) -> GitCommand {
        .changing(["reset", "--quiet", "--\(mode.rawValue)", commit])
    }

    /// A merge is finished by committing it. `message` replaces Git's own when it isn't empty.
    static func continueOperation(_ stopped: Stopped, message: String = "") -> GitCommand {
        var command: GitCommand
        switch stopped {
        case .merge:
            command = .changing(["commit"] + (message.isEmpty ? ["--no-edit"] : ["--message=" + message]))
        case .rebase, .cherryPick, .revert:
            command = .changing([stopped.name, "--continue"])
        }
        command.environment = keepMessage
        return command
    }

    /// Nil for a merge, which has no commit to skip.
    static func skip(_ stopped: Stopped) -> GitCommand? {
        guard stopped != .merge else { return nil }
        var command = GitCommand.changing([stopped.name, "--skip"])
        command.environment = keepMessage
        return command
    }

    static func abort(_ stopped: Stopped) -> GitCommand {
        .changing([stopped.name, "--abort"])
    }

    /// Exits 0 when `commit` is in the history of `revision`.
    static func isAncestor(_ commit: String, of revision: String) -> GitCommand {
        .reading(["merge-base", "--is-ancestor", commit, revision])
    }
}
