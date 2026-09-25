import Foundation

/// One repository on the dashboard's list.
nonisolated struct DashboardRow: Equatable, Identifiable {
    let entry: RecentRepository
    /// The folder name, with parent folders added when another repository shares it.
    let folderName: String

    var id: String {
        entry.id
    }

    var repository: Repository {
        entry.repository
    }

    var name: String {
        entry.displayName ?? folderName
    }

    static func rows(for entries: [RecentRepository]) -> [DashboardRow] {
        zip(entries, DistinctFolderNames.make(for: entries.map(\.repository.workTree))).map(DashboardRow.init)
    }
}

/// The recent list prepared for searching, which is rebuilt only when the list changes rather than
/// on every keystroke.
nonisolated struct DashboardSearch {
    let entries: [RecentRepository]
    let rows: [DashboardRow]
    /// A display name and a folder name each match, so either finds the repository.
    private let matchers: [[FuzzyMatcher]]

    init(entries: [RecentRepository]) {
        self.entries = entries
        rows = DashboardRow.rows(for: entries)
        matchers = rows.map { row in
            [row.entry.displayName, row.folderName].compactMap(\.self).map(FuzzyMatcher.init(name:))
        }
    }

    /// Repositories opened for this term before come first, then the best matches. Equal matches
    /// keep the recent list's order, most recent first.
    func filter(_ query: String, among shown: (DashboardRow) -> Bool, boosts: [String: Double]) -> [DashboardRow] {
        let term = Array(FuzzyMatcher.fold(query))
        guard !term.isEmpty else {
            return rows.filter(shown)
        }

        struct Match {
            let row: DashboardRow
            let boost: Double
            let score: Int
            let position: Int
        }
        let matches = rows.indices.compactMap { position -> Match? in
            let row = rows[position]
            guard shown(row), let score = matchers[position].compactMap({ $0.score(term) }).max() else {
                return nil
            }
            return Match(row: row, boost: boosts[row.id] ?? 0, score: score, position: position)
        }
        return matches
            .sorted { lhs, rhs in
                if lhs.boost != rhs.boost {
                    return lhs.boost > rhs.boost
                }
                return lhs.score != rhs.score ? lhs.score > rhs.score : lhs.position < rhs.position
            }
            .map(\.row)
    }
}
