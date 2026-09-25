import Foundation

/// What the dashboard shows: the recent list filtered by the search, the selected row, and what
/// each repository's latest check found.
@Observable
final class DashboardSession {
    var query = "" {
        didSet { selectedID = nil }
    }

    /// Changes each time the dashboard is asked to open, which is when the search field takes focus.
    private(set) var openCount = 0
    private(set) var states: [String: RecentRepositoryState] = [:]
    /// Nil selects the first row, so the best match stays selected as the user types.
    private var selectedID: String?

    @ObservationIgnored private let recents: RecentRepositoryStore

    init(recents: RecentRepositoryStore) {
        self.recents = recents
    }

    var hasRecentRepositories: Bool {
        !recents.repositories.isEmpty
    }

    var rows: [DashboardRow] {
        DashboardSearch.filter(DashboardRow.rows(for: recents.repositories), by: query)
    }

    var selectedRow: DashboardRow? {
        let rows = rows
        return rows.first { $0.id == selectedID } ?? rows.first
    }

    func opened(clearingSearch: Bool) {
        if clearingSearch {
            query = ""
        }
        openCount += 1
    }

    func select(_ row: DashboardRow) {
        selectedID = row.id
    }

    func moveSelection(by offset: Int) {
        let rows = rows
        guard let selectedRow, let index = rows.firstIndex(of: selectedRow) else { return }
        selectedID = rows[min(max(index + offset, 0), rows.count - 1)].id
    }

    /// The row that takes its place is selected, so pressing the shortcut again keeps removing.
    func remove(_ row: DashboardRow) {
        let index = rows.firstIndex(of: row)
        recents.remove(row.repository)
        let remaining = rows
        if let index, !remaining.isEmpty {
            selectedID = remaining[min(index, remaining.count - 1)].id
        }
    }

    func record(_ state: RecentRepositoryState, for repository: Repository) {
        states[repository.id] = state
    }
}
