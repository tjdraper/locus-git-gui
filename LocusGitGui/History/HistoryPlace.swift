/// Where the user left a history: the row selected, and the commit at the top of the list.
nonisolated struct HistoryPlace: Codable, Equatable, Sendable {
    enum Selection: Codable, Equatable, Sendable {
        case workingArea
        case commit(String)
    }

    var selection: Selection?
    /// Nil at the very top of the list, where every history starts.
    var topCommit: String?
}

/// Where each history was left, by what the sidebar had selected, nil being the checked-out
/// branch's. Only the most recently left are kept, since every branch and tag looked at could
/// otherwise add one to the repository's saved view state.
nonisolated struct HistoryPlaceMemory: Codable, Equatable, Sendable {
    private struct Entry: Codable, Equatable, Sendable {
        let scope: SidebarItemID?
        let place: HistoryPlace
    }

    static let limit = 200

    /// Oldest first.
    private var entries: [Entry] = []

    /// Nil for a history never left anywhere.
    func place(for scope: SidebarItemID?) -> HistoryPlace? {
        entries.last { $0.scope == scope }?.place
    }

    mutating func set(_ place: HistoryPlace, for scope: SidebarItemID?) {
        entries.removeAll { $0.scope == scope }
        entries.append(Entry(scope: scope, place: place))
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
    }
}
