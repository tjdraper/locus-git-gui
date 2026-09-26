/// The commits a history starts from, for whatever the sidebar has selected. They're hashes rather
/// than ref names, so every page of one history is read from the same commits even while a branch
/// moves, and a history whose commits haven't moved doesn't need reading again.
nonisolated struct HistoryScope: Equatable, Sendable {
    let tips: [String]

    /// With nothing selected, the checked-out branch, or HEAD when it's detached. A remote stands
    /// for all its branches. Nil `head` is a repository with no commits yet.
    static func resolve(selection: SidebarItemID?, refs: [Ref], contents: SidebarContents?, head: String?) -> HistoryScope {
        func commit(of name: String) -> String? {
            refs.first { $0.name == name }?.commit
        }
        switch selection {
        case let .ref(name):
            if let tip = commit(of: name) {
                return HistoryScope(tips: [tip])
            }
        case let .remote(name):
            if let remote = contents?.remotes.first(where: { $0.name == name }) {
                let tips = remote.branches.compactMap { branch -> String? in
                    guard case let .ref(name) = branch.id else { return nil }
                    return commit(of: name)
                }
                return HistoryScope(tips: unique(tips))
            }
        case let .stash(commit):
            return HistoryScope(tips: [commit])
        case nil:
            break
        }
        return HistoryScope(tips: head.map { [$0] } ?? [])
    }

    /// Several branches of a remote often point at the same commit.
    private static func unique(_ tips: [String]) -> [String] {
        var seen: Set<String> = []
        return tips.filter { seen.insert($0).inserted }
    }
}
