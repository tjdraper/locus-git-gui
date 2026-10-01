import Foundation

/// Where a review's two points were between one move and the next. A new revision is recorded
/// whenever either point moves.
nonisolated struct ReviewRevision: Codable, Equatable, Sendable {
    let base: String
    /// For the working tree, the commit it's on.
    let head: String
    let includesWorkingTree: Bool
    /// Where the head split from the base. The head is compared against it rather than the base,
    /// as a pull request is, so new commits on the base don't show up as the head's changes.
    let mergeBase: String?
    let recorded: Date

    /// Where both points are as of a refresh, before anything is read.
    struct Place: Equatable, Sendable {
        let base: String
        let head: String
        let includesWorkingTree: Bool
    }

    var place: Place {
        Place(base: base, head: head, includesWorkingTree: includesWorkingTree)
    }

    /// What the head side is compared against.
    var comparedBase: String {
        mergeBase ?? base
    }

    /// Nil for the working tree, which `git diff` compares against when given one commit.
    var comparedHead: String? {
        includesWorkingTree ? nil : head
    }

    init(_ place: Place, mergeBase: String?, recorded: Date) {
        base = place.base
        head = place.head
        includesWorkingTree = place.includesWorkingTree
        self.mergeBase = mergeBase
        self.recorded = recorded
    }

    /// Nil while either point can't be found, which leaves the review where it last was.
    static func place(base: ReviewPoint.Resolution, head: ReviewPoint.Resolution) -> Place? {
        guard case let .commit(baseCommit) = base else { return nil }
        switch head {
        case let .commit(headCommit):
            return Place(base: baseCommit, head: headCommit, includesWorkingTree: false)
        case let .workingTree(headCommit):
            return Place(base: baseCommit, head: headCommit, includesWorkingTree: true)
        case .missing:
            return nil
        }
    }

    /// `git merge-base` exits 1 when the two share no history, which leaves the base to compare
    /// against directly.
    static func mergeBaseCommand(_ place: Place) -> GitCommand {
        .reading(["merge-base", "--end-of-options", place.base, place.head])
    }

    static func parseMergeBase(_ result: ChildProcess.Result) -> String? {
        guard result.status == 0, let output = String(bytes: result.standardOutput, encoding: .utf8) else { return nil }
        let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }
}
