import Foundation

/// One side of a review: where in the repository it's compared from or to.
nonisolated enum ReviewPoint: Codable, Hashable, Sendable {
    /// A local branch, a remote branch or a tag by its full name, followed as it moves.
    case ref(String)
    /// Stays where it is until moved by hand.
    case commit(String)
    /// HEAD, which moves with each commit and checkout.
    case checkedOut
    /// Everything uncommitted: staged, unstaged and untracked.
    case workingTree

    /// Where a point is as of a refresh.
    enum Resolution: Equatable, Sendable {
        case commit(String)
        /// The working tree, on top of the checked-out commit.
        case workingTree(String)
        /// A followed ref that no longer exists, or a repository with no commits yet.
        case missing
    }

    var title: String {
        switch self {
        case let .ref(name): Self.shortName(of: name)
        case let .commit(hash): String(hash.prefix(7))
        case .checkedOut: "HEAD"
        case .workingTree: "Uncommitted Changes"
        }
    }

    /// A branch or tag moves the review along with it.
    var follows: Bool {
        if case .commit = self { false } else { true }
    }

    var isWorkingTree: Bool {
        self == .workingTree
    }

    /// Resolved from what a refresh has already read, so following every review costs no command.
    func resolve(in refs: [Ref], head: String?) -> Resolution {
        switch self {
        case let .ref(name):
            refs.first { $0.name == name }.map { .commit($0.commit) } ?? .missing
        case let .commit(hash):
            .commit(hash)
        case .checkedOut:
            head.map { .commit($0) } ?? .missing
        case .workingTree:
            head.map { .workingTree($0) } ?? .missing
        }
    }

    static func shortName(of ref: String) -> String {
        for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] where ref.hasPrefix(prefix) {
            return String(ref.dropFirst(prefix.count))
        }
        return ref
    }
}
