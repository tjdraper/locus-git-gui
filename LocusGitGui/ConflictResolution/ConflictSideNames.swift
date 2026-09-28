import Foundation

/// What the conflict window calls each side. Git's "ours" and "theirs" swap meaning in a rebase,
/// where ours is the branch being rebased onto, so each side is named for what it is instead: the
/// checked-out branch, or in a rebase the branch it's going onto, and the branch or commit being
/// brought in, as Git labels it in the file.
nonisolated struct ConflictSideNames: Equatable, Sendable {
    let ours: String
    let theirs: String

    /// `theirsLabel` is what Git wrote after a conflict's closing marker, and `theirsCommit` names
    /// the commit being brought in, for a file with no markers to read it from.
    init(
        operation: InProgressOperation?,
        checkedOutBranch: String?,
        rebaseOnto: String?,
        theirsLabel: String?,
        theirsCommit: String?
    ) {
        ours = if case .rebasing = operation {
            rebaseOnto ?? "HEAD"
        } else {
            checkedOutBranch ?? "HEAD"
        }
        let label = theirsLabel?.trimmingCharacters(in: .whitespaces)
        if let label, !label.isEmpty {
            theirs = label
        } else if let theirsCommit {
            theirs = theirsCommit
        } else {
            theirs = "Theirs"
        }
    }

    init(ours: String, theirs: String) {
        self.ours = ours
        self.theirs = theirs
    }

    /// The commit being brought in, from the files Git keeps while an operation waits: the branch
    /// being merged, the commit being cherry-picked or reverted, or the one a rebase stopped at.
    static func readTheirsCommit(gitDirectory: URL) -> String? {
        let files = ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge/stopped-sha", "rebase-apply/original-commit"]
        return files.lazy.compactMap { firstLine(of: gitDirectory.appending(path: $0)) }.first
    }

    /// The commit a rebase is putting the branch's commits on top of.
    static func readRebaseOnto(gitDirectory: URL) -> String? {
        firstLine(of: gitDirectory.appending(path: "rebase-merge/onto")) ?? firstLine(of: gitDirectory.appending(path: "rebase-apply/onto"))
    }

    /// A local branch at `commit` names it best, then a remote branch, then its short hash.
    static func name(of commit: String, in refs: [Ref]) -> String {
        let branches = refs.filter { $0.commit == commit }
        if let local = branches.first(where: { $0.kind == .localBranch }) {
            return String(local.name.dropFirst("refs/heads/".count))
        }
        if let remote = branches.first(where: { $0.kind == .remoteBranch }) {
            return String(remote.name.dropFirst("refs/remotes/".count))
        }
        return String(commit.prefix(7))
    }

    private static func firstLine(of url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first
        else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
