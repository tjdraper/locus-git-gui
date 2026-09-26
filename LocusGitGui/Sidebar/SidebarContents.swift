import Foundation

/// Everything the sidebar lists, in the order it lists it. What's pinned is listed in its own section
/// at the top rather than in the section it would otherwise be in, but stays in these lists, which
/// the history and the command palette read.
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

    enum PinnedItem: Equatable, Sendable, Identifiable {
        case branch(Branch)
        /// With the remote's name in front, since it isn't listed under its remote.
        case remoteBranch(RemoteBranch, name: String)
        case tag(Tag)
        case stash(StashEntry)

        var id: SidebarItemID {
            switch self {
            case let .branch(branch): branch.id
            case let .remoteBranch(branch, _): branch.id
            case let .tag(tag): tag.id
            case let .stash(stash): stash.id
            }
        }

        var name: String {
            switch self {
            case let .branch(branch): branch.name
            case let .remoteBranch(_, name): name
            case let .tag(tag): tag.name
            case let .stash(stash): stash.message
            }
        }
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
    /// In the order they were pinned, leaving out pins for what the repository doesn't have.
    let pinned: [PinnedItem]
    private let pinnedIDs: Set<SidebarItemID>

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
        pinned = []
        pinnedIDs = []
    }

    private init(branches: [Branch], remotes: [Remote], tags: [Tag], stashes: [StashEntry], pinned: [PinnedItem]) {
        self.branches = branches
        self.remotes = remotes
        self.tags = tags
        self.stashes = stashes
        self.pinned = pinned
        pinnedIDs = Set(pinned.map(\.id))
    }

    func pinning(_ pins: SidebarPins) -> SidebarContents {
        let pinned = pins.items.compactMap { id -> PinnedItem? in
            if let branch = branches.first(where: { $0.id == id }) {
                return .branch(branch)
            }
            for remote in remotes {
                if let branch = remote.branches.first(where: { $0.id == id }) {
                    return .remoteBranch(branch, name: remote.name + "/" + branch.name)
                }
            }
            if let tag = tags.first(where: { $0.id == id }) {
                return .tag(tag)
            }
            return stashes.first { $0.id == id }.map(PinnedItem.stash)
        }
        return SidebarContents(branches: branches, remotes: remotes, tags: tags, stashes: stashes, pinned: pinned)
    }

    func isPinned(_ id: SidebarItemID) -> Bool {
        pinnedIDs.contains(id)
    }

    /// The branches listed in their own section, which leaves out the pinned ones. The same goes for
    /// the rest.
    var unpinnedBranches: [Branch] {
        branches.filter { !isPinned($0.id) }
    }

    var unpinnedRemotes: [Remote] {
        guard !pinnedIDs.isEmpty else { return remotes }
        return remotes.map { remote in
            Remote(name: remote.name, branches: remote.branches.filter { !isPinned($0.id) })
        }
    }

    var unpinnedTags: [Tag] {
        tags.filter { !isPinned($0.id) }
    }

    var unpinnedStashes: [StashEntry] {
        stashes.filter { !isPinned($0.id) }
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
            stashes: stashes.filter { matches($0.message) },
            pinned: pinned.filter { matches($0.name) }
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
        if isPinned(id) {
            return .pinned
        }
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

    /// The remote a remote branch is listed under, which a pinned one isn't.
    func remote(containing id: SidebarItemID) -> String? {
        guard !isPinned(id) else { return nil }
        return remotes.first { $0.branches.contains { $0.id == id } }?.name
    }

    /// Only the rows that can be seen: none from a collapsed section or under a collapsed remote.
    func visibleRows(collapsedSections: Set<SidebarSection>, collapsedRemotes: Set<String>) -> [Row] {
        var rows: [Row] = []
        if !collapsedSections.contains(.pinned) {
            rows += pinned.map { Row(id: $0.id, name: $0.name) }
        }
        if !collapsedSections.contains(.branches) {
            rows += unpinnedBranches.map { Row(id: $0.id, name: $0.name) }
        }
        if !collapsedSections.contains(.remotes) {
            for remote in unpinnedRemotes {
                rows.append(Row(id: remote.id, name: remote.name))
                if !collapsedRemotes.contains(remote.name) {
                    rows += remote.branches.map { Row(id: $0.id, name: $0.name) }
                }
            }
        }
        if !collapsedSections.contains(.tags) {
            rows += unpinnedTags.map { Row(id: $0.id, name: $0.name) }
        }
        if !collapsedSections.contains(.stashes) {
            rows += unpinnedStashes.map { Row(id: $0.id, name: $0.message) }
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
