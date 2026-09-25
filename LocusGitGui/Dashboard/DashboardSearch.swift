import Foundation

/// One repository on the dashboard's list.
nonisolated struct DashboardRow: Equatable, Identifiable {
    let repository: Repository
    /// The folder name, with parent folders added when another repository shares it.
    let name: String

    var id: String {
        repository.id
    }

    static func rows(for repositories: [Repository]) -> [DashboardRow] {
        zip(repositories, DistinctFolderNames.make(for: repositories.map(\.workTree))).map(DashboardRow.init)
    }
}

/// Filters the dashboard's list as the user types.
nonisolated enum DashboardSearch {
    /// The best matches first. Equal matches keep the recent list's order, most recent first.
    static func filter(_ rows: [DashboardRow], by query: String) -> [DashboardRow] {
        let term = Array(FuzzyMatcher.fold(query))
        guard !term.isEmpty else {
            return rows
        }
        struct Match {
            let row: DashboardRow
            let score: Int
            let position: Int
        }
        let matches = rows.enumerated().compactMap { position, row in
            FuzzyMatcher(name: row.name).score(term).map { Match(row: row, score: $0, position: position) }
        }
        return matches
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.position < $1.position }
            .map(\.row)
    }
}
