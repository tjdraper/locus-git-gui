import Foundation

/// Keeps the file contents a review's checks and comments refer to in the repository. Git deletes
/// what nothing points at, which after a force push or a rebase includes the versions a review
/// was checked against. A hidden ref for each review points at a tree holding them all.
///
/// The ref is outside `refs/heads` and `refs/tags`, so pushing and cloning leave it behind, and a
/// tree rather than a commit, so `git log --all` in Terminal doesn't show it.
nonisolated enum ReviewKeptObjects {
    static let refPrefix = "refs/locus/reviews/"

    static func ref(for review: UUID) -> String {
        refPrefix + review.uuidString.lowercased()
    }

    /// Each object is named by its own hash, which is unique within the tree and needs no escaping.
    static func treeCommand(_ objects: Set<String>) -> GitCommand {
        let entries = objects.sorted().map { "100644 blob \($0)\t\($0)\0" }.joined()
        return .changing(["mktree", "-z"], input: Data(entries.utf8))
    }

    static func pointCommand(for review: UUID, at tree: String) -> GitCommand {
        .changing(["update-ref", "--no-deref", ref(for: review), tree])
    }

    static func deleteCommand(for review: UUID) -> GitCommand {
        .changing(["update-ref", "--no-deref", "-d", ref(for: review)])
    }
}
