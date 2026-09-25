import Foundation

/// What the dashboard shows: the recent list filtered by the search and the missing filter, the
/// selected rows, and what each repository's latest check found.
@Observable
final class DashboardSession {
    private static let historyKey = "DashboardOpenHistory"

    var query = "" {
        didSet { selection = DashboardSelection() }
    }

    var showsOnlyMissing = false {
        didSet { selection = DashboardSelection() }
    }

    /// Changes each time the search field should take focus: whenever the dashboard is asked to
    /// open, and when a sheet over it closes.
    private(set) var searchFocusRequests = 0
    /// From the file system, for every repository.
    private var presences: [String: RepositoryPresence] = [:]
    /// From Git, for the repositories whose rows have been on screen.
    private var checkedStates: [String: RecentRepositoryState] = [:]
    private var selection = DashboardSelection()

    @ObservationIgnored private let recents: RecentRepositoryStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var history: SearchPickHistory
    @ObservationIgnored private var search = DashboardSearch(entries: [])

    init(recents: RecentRepositoryStore, defaults: UserDefaults = .standard) {
        self.recents = recents
        self.defaults = defaults
        history = SearchPickHistory(defaults: defaults, key: Self.historyKey)
    }

    var hasRecentRepositories: Bool {
        !recents.entries.isEmpty
    }

    var rows: [DashboardRow] {
        let entries = recents.entries
        if search.entries != entries {
            search = DashboardSearch(entries: entries)
        }
        let missing = showsOnlyMissing ? Set(missingRepositories.map(\.id)) : []
        return search.filter(
            query,
            among: { missing.isEmpty || missing.contains($0.id) },
            boosts: history.boosts(for: FuzzyMatcher.fold(query), at: .now)
        )
    }

    /// In the order they're shown.
    var selectedRows: [DashboardRow] {
        let rows = rows
        let selected = Set(selection.selected(in: rows.map(\.id)))
        return rows.filter { selected.contains($0.id) }
    }

    var cursorID: String? {
        selection.currentCursor(in: rows.map(\.id))
    }

    var missingRepositories: [Repository] {
        recents.entries.filter { state(of: $0.id) == .missing }.map(\.repository)
    }

    /// Nil until something is known about it.
    func state(of id: String) -> RecentRepositoryState? {
        switch presences[id] {
        case .missing:
            .missing
        case .driveNotConnected:
            .driveNotConnected
        case .present, nil:
            checkedStates[id]
        }
    }

    /// Both need the repository's folder to be there.
    func canSetDisplayName(of row: DashboardRow) -> Bool {
        canShowInFinder(row)
    }

    func canShowInFinder(_ row: DashboardRow) -> Bool {
        state(of: row.id) != .missing && state(of: row.id) != .driveNotConnected
    }

    func opened(clearingSearch: Bool) {
        if clearingSearch {
            query = ""
            showsOnlyMissing = false
        }
        focusSearch()
    }

    func focusSearch() {
        searchFocusRequests += 1
    }

    func click(_ row: DashboardRow, extending: Bool, toggling: Bool) {
        selection.click(row.id, in: rows.map(\.id), extending: extending, toggling: toggling)
    }

    func moveSelection(by offset: Int, extending: Bool) {
        selection.move(by: offset, in: rows.map(\.id), extending: extending)
    }

    /// Repositories opened after typing a search come first for that search next time.
    func noteOpened(_ rows: [DashboardRow]) {
        let term = FuzzyMatcher.fold(query)
        guard !term.isEmpty else { return }
        for row in rows {
            history.record(term: term, item: row.id, at: .now)
        }
        history.save(to: defaults, key: Self.historyKey)
    }

    func remove(_ repositories: [Repository]) -> [RecentRepositoryList.Removal] {
        selection.selectAfterRemoving(Set(repositories.map(\.id)), from: rows.map(\.id))
        let removed = recents.remove(repositories)
        if missingRepositories.isEmpty {
            showsOnlyMissing = false
        }
        return removed
    }

    func restore(_ removed: [RecentRepositoryList.Removal]) {
        recents.restore(removed)
    }

    func record(_ state: RecentRepositoryState, for repository: Repository) {
        checkedStates[repository.id] = state
    }

    func record(_ findings: [RecentRepositoryChecker.Finding]) {
        for finding in findings {
            presences[finding.repository.id] = finding.presence
            if finding.presence == .present {
                recents.setDisplayName(finding.displayName, for: finding.repository)
            }
        }
        if missingRepositories.isEmpty {
            showsOnlyMissing = false
        }
    }
}
