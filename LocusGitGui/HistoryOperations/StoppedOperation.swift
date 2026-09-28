import Foundation

/// A merge, rebase, cherry-pick or revert that stopped partway, as the window's status and the
/// conflict window describe it: what's underway, and what it's waiting for.
nonisolated struct StoppedOperation: Equatable, Sendable {
    let kind: HistoryOperationCommand.Stopped
    let title: String
    let detail: String

    /// Nil when nothing has stopped, and for a bisect, which the app has no commands for.
    /// `editing` is the commit an edit stopped at, and `conflicts` how many files still have them.
    init?(_ operation: InProgressOperation?, branch: String?, conflicts: Int, editing: String?) {
        let onto = branch.map { " “\($0)”" } ?? ""
        switch operation {
        case .merging:
            kind = .merge
            title = "Merging into\(onto)"
        case let .rebasing(rebased, step, total):
            kind = .rebase
            let name = (rebased ?? branch).map { " “\($0)”" } ?? ""
            title = step.flatMap { step in total.map { "Rebasing\(name), \(step) of \($0)" } } ?? "Rebasing\(name)"
        case .cherryPicking:
            kind = .cherryPick
            title = "Cherry-picking onto\(onto)"
        case .reverting:
            kind = .revert
            title = "Reverting on\(onto)"
        case .bisecting, nil:
            return nil
        }
        detail = Self.detail(kind, conflicts: conflicts, editing: editing)
    }

    private static func detail(_ kind: HistoryOperationCommand.Stopped, conflicts: Int, editing: String?) -> String {
        if conflicts > 0 {
            let files = conflicts == 1 ? "1 file has conflicts" : "\(conflicts) files have conflicts"
            return "\(files). Resolve and stage each one, then Continue."
        }
        if let editing {
            return "Stopped at \(editing.prefix(7)) to edit it. Change it and stage the changes, then Continue."
        }
        switch kind {
        case .merge: return "Every conflict is resolved. Continue makes the merge commit."
        case .rebase: return "Every conflict is resolved. Continue carries on with the commits after it."
        case .cherryPick, .revert: return "Every conflict is resolved. Continue makes the commit."
        }
    }

    /// The commit an interactive rebase stopped at to be edited. While it waits at an `edit`, Git
    /// keeps an `amend` file in the rebase's folder, beside `stopped-sha`, which names the commit.
    static func editedCommit(gitDirectory: URL) -> String? {
        let folder = gitDirectory.appending(path: "rebase-merge")
        guard FileManager.default.fileExists(atPath: folder.appending(path: "amend").path),
              let hash = try? String(contentsOf: folder.appending(path: "stopped-sha"), encoding: .utf8)
        else { return nil }
        let trimmed = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
