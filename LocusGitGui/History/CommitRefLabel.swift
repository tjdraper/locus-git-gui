import Foundation

/// A branch, remote branch or tag shown on the commit it points at.
nonisolated struct CommitRefLabel: Equatable, Hashable, Sendable {
    enum Kind: Int, Comparable, Sendable {
        /// HEAD when it's detached, which no branch marks.
        case head
        case checkedOutBranch
        case branch
        case remoteBranch
        case tag

        static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let kind: Kind
    /// As Git shortens it, such as `main`, `origin/main` or `v1.2`.
    let name: String
    /// The sidebar row it's listed as, which HEAD has none of.
    let sidebarItem: SidebarItemID?

    /// Every commit that has a label, with its labels in the order they're shown: HEAD and the
    /// checked-out branch first, then branches, remote branches and tags.
    static func byCommit(refs: [Ref], detachedHead: String?) -> [String: [CommitRefLabel]] {
        var labels: [String: [CommitRefLabel]] = [:]
        if let detachedHead {
            labels[detachedHead] = [CommitRefLabel(kind: .head, name: "HEAD", sidebarItem: nil)]
        }
        for ref in refs where ref.symbolicTarget == nil {
            guard let label = label(for: ref) else { continue }
            labels[ref.commit, default: []].append(label)
        }
        return labels.mapValues { labels in
            labels.sorted { first, second in
                first.kind != second.kind
                    ? first.kind < second.kind
                    : first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
        }
    }

    private static func label(for ref: Ref) -> CommitRefLabel? {
        let kind: Kind
        let prefix: String
        switch ref.kind {
        case .localBranch:
            kind = ref.isCheckedOut ? .checkedOutBranch : .branch
            prefix = "refs/heads/"
        case .remoteBranch:
            kind = .remoteBranch
            prefix = "refs/remotes/"
        case .tag:
            kind = .tag
            prefix = "refs/tags/"
        case nil:
            return nil
        }
        return CommitRefLabel(kind: kind, name: String(ref.name.dropFirst(prefix.count)), sidebarItem: .ref(ref.name))
    }
}
