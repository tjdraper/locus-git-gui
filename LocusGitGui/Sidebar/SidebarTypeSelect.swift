import Foundation

/// Jumps to a row by typing the start of its name, as a Finder list does. Keys typed in quick
/// succession add to one search; a pause starts a new one.
nonisolated struct SidebarTypeSelect {
    /// About as long as AppKit's own type-to-select waits.
    static let pause: TimeInterval = 1

    private(set) var search = ""
    private var lastTyped: Date?

    /// The index of the row to select, or nil when nothing matches. A new search starts after the
    /// selected row, so typing the same letter again after a pause moves on to the next match. A
    /// longer search starts at the selected row, which stays selected while it still matches.
    mutating func select(typing characters: String, at date: Date, in names: [String], selected: Int?) -> Int? {
        let isNewSearch = lastTyped.map { date.timeIntervalSince($0) > Self.pause } ?? true
        lastTyped = date
        search = isNewSearch ? characters : search + characters
        guard !names.isEmpty else { return nil }

        let start = selected.map { isNewSearch ? $0 + 1 : $0 } ?? 0
        for offset in 0 ..< names.count {
            let index = (start + offset) % names.count
            if names[index].range(of: search, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil {
                return index
            }
        }
        return nil
    }
}
