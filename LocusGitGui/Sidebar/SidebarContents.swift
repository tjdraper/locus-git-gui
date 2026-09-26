import Foundation

/// Everything the sidebar lists, in the order it lists it.
nonisolated struct SidebarContents: Equatable, Sendable {
    struct Branch: Equatable, Sendable, Identifiable {
        let id: SidebarItemID
        let name: String
        let isCheckedOut: Bool
        /// Short, such as `origin/main`.
        let upstream: String?
        let ahead: Int?
        let behind: Int?
        let isUpstreamGone: Bool
    }

    struct Remote: Equatable, Sendable, Identifiable {
        let name: String
        let branches: [RemoteBranch]

        var id: SidebarItemID {
            .remote(name)
        }
    }

    struct RemoteBranch: Equatable, Sendable, Identifiable {
        let id: SidebarItemID
        /// Without the remote's name, which the row it's listed under already shows.
        let name: String
    }

    struct Tag: Equatable, Sendable, Identifiable {
        let id: SidebarItemID
        let name: String
    }

    struct StashEntry: Equatable, Sendable, Identifiable {
        let id: SidebarItemID
        let message: String
        let date: Date
    }

    /// A row as the keyboard reaches it: what it stands for, and the name type-to-select matches.
    struct Row: Equatable {
        let id: SidebarItemID
        let name: String
    }

    let branches: [Branch]
    let remotes: [Remote]
    let tags: [Tag]
    let stashes: [StashEntry]

    /// With the refs already read, since the history needs them too.
    static func read(refs: [Ref], running run: (GitCommand) async throws -> ChildProcess.Result) async throws -> SidebarContents {
        let remotes = try await GitReadFailure.read("remotes", with: RemoteName.listCommand, running: run, parse: RemoteName.parseList)
        let stashes = try await GitReadFailure.read("stashes", with: Stash.listCommand, running: run, parse: Stash.parseList)
        return SidebarContents(refs: refs, remoteNames: remotes, stashes: stashes)
    }

    init(refs: [Ref], remoteNames: [String], stashes: [Stash]) {
        branches = refs.filter { $0.kind == .localBranch }
            .map { ref in
                Branch(
                    id: .ref(ref.name),
                    name: String(ref.name.dropFirst("refs/heads/".count)),
                    isCheckedOut: ref.isCheckedOut,
                    upstream: ref.upstream.map(Self.shortName),
                    ahead: ref.ahead,
                    behind: ref.behind,
                    isUpstreamGone: ref.isUpstreamGone
                )
            }
            .sorted { Self.precedes($0.name, $1.name) }
        remotes = Self.remotes(named: remoteNames, from: refs.filter { $0.kind == .remoteBranch && $0.symbolicTarget == nil })
        // Newest first, which for version numbers is the highest.
        tags = refs.filter { $0.kind == .tag }
            .map { Tag(id: .ref($0.name), name: String($0.name.dropFirst("refs/tags/".count))) }
            .sorted { Self.precedes($1.name, $0.name) }
        self.stashes = stashes.map { StashEntry(id: .stash($0.commit), message: $0.message, date: $0.date) }
    }

    private init(branches: [Branch], remotes: [Remote], tags: [Tag], stashes: [StashEntry]) {
        self.branches = branches
        self.remotes = remotes
        self.tags = tags
        self.stashes = stashes
    }

    /// Only what has the text anywhere in its name, ignoring case and accents. A remote branch
    /// matches with its remote's name in front, so `origin/main` finds it. A remote whose own name
    /// matches keeps all its branches.
    func filtered(by text: String) -> SidebarContents {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return self }
        func matches(_ name: String) -> Bool {
            name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return SidebarContents(
            branches: branches.filter { matches($0.name) },
            remotes: remotes.compactMap { remote in
                if matches(remote.name) {
                    return remote
                }
                let branches = remote.branches.filter { matches(remote.name + "/" + $0.name) }
                return branches.isEmpty ? nil : Remote(name: remote.name, branches: branches)
            },
            tags: tags.filter { matches($0.name) },
            stashes: stashes.filter { matches($0.message) }
        )
    }

    var isEmpty: Bool {
        branches.isEmpty && remotes.isEmpty && tags.isEmpty && stashes.isEmpty
    }

    func contains(_ id: SidebarItemID) -> Bool {
        switch id {
        case .ref:
            branches.contains { $0.id == id } || tags.contains { $0.id == id }
                || remotes.contains { $0.branches.contains { $0.id == id } }
        case .remote:
            remotes.contains { $0.id == id }
        case .stash:
            stashes.contains { $0.id == id }
        }
    }

    /// Which section lists it, or nil when nothing here is it.
    func section(containing id: SidebarItemID) -> SidebarSection? {
        guard contains(id) else { return nil }
        switch id {
        case .ref:
            if branches.contains(where: { $0.id == id }) {
                return .branches
            }
            return tags.contains { $0.id == id } ? .tags : .remotes
        case .remote:
            return .remotes
        case .stash:
            return .stashes
        }
    }

    /// The remote a remote branch is listed under.
    func remote(containing id: SidebarItemID) -> String? {
        remotes.first { $0.branches.contains { $0.id == id } }?.name
    }

    /// Only the rows that can be seen: none from a collapsed section or under a collapsed remote.
    func visibleRows(collapsedSections: Set<SidebarSection>, collapsedRemotes: Set<String>) -> [Row] {
        var rows: [Row] = []
        if !collapsedSections.contains(.branches) {
            rows += branches.map { Row(id: $0.id, name: $0.name) }
        }
        if !collapsedSections.contains(.remotes) {
            for remote in remotes {
                rows.append(Row(id: remote.id, name: remote.name))
                if !collapsedRemotes.contains(remote.name) {
                    rows += remote.branches.map { Row(id: $0.id, name: $0.name) }
                }
            }
        }
        if !collapsedSections.contains(.tags) {
            rows += tags.map { Row(id: $0.id, name: $0.name) }
        }
        if !collapsedSections.contains(.stashes) {
            rows += stashes.map { Row(id: $0.id, name: $0.message) }
        }
        return rows
    }

    /// Branches whose remote has been removed from the config still have refs until they're
    /// pruned, so they're listed under a remote of their own name.
    private static func remotes(named names: [String], from refs: [Ref]) -> [Remote] {
        // Longest first, so a remote named `a/b` claims `refs/remotes/a/b/main` before `a` does.
        let byLength = names.sorted { $0.count > $1.count }
        var branches: [String: [RemoteBranch]] = [:]
        var order = names
        for ref in refs {
            let path = ref.name.dropFirst("refs/remotes/".count)
            let remote = byLength.first { path.hasPrefix($0 + "/") }
                ?? String(path.prefix { $0 != "/" })
            if !order.contains(remote) {
                order.append(remote)
            }
            let name = String(path.dropFirst(remote.count + 1))
            branches[remote, default: []].append(RemoteBranch(id: .ref(ref.name), name: name))
        }
        return order.map { name in
            Remote(name: name, branches: (branches[name] ?? []).sorted { precedes($0.name, $1.name) })
        }
    }

    /// As Finder sorts, so `v1.10` comes after `v1.9` and case doesn't split the list in two.
    private static func precedes(_ first: String, _ second: String) -> Bool {
        first.localizedStandardCompare(second) == .orderedAscending
    }

    private static func shortName(_ ref: String) -> String {
        for prefix in ["refs/remotes/", "refs/heads/"] where ref.hasPrefix(prefix) {
            return String(ref.dropFirst(prefix.count))
        }
        return ref
    }
}
