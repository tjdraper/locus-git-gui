import Foundation

/// Which repositories were opened from the dashboard after typing which search terms, so the one
/// picked for a term comes first the next time it's typed. Each pick's weight halves every couple
/// of weeks, so recent picks outrank old habits. Ported from Locus Launcher's launch history.
nonisolated struct DashboardOpenHistory: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let term: String
        /// The repository's `id`.
        let repository: String
        var weight: Double
        var updated: Date

        func weight(at date: Date) -> Double {
            weight * pow(0.5, date.timeIntervalSince(updated) / DashboardOpenHistory.halfLife)
        }
    }

    static let halfLife: TimeInterval = 14 * 24 * 60 * 60
    /// About seven weeks after a single pick.
    private static let forgottenWeight = 0.1
    private static let maxEntries = 1000

    private(set) var entries: [Entry] = []

    /// Takes a term already passed through `FuzzyMatcher.fold`.
    mutating func record(term: String, repository: String, at date: Date) {
        guard !term.isEmpty else { return }

        if let index = entries.firstIndex(where: { $0.term == term && $0.repository == repository }) {
            entries[index].weight = entries[index].weight(at: date) + 1
            entries[index].updated = date
        } else {
            entries.append(Entry(term: term, repository: repository, weight: 1, updated: date))
        }
        entries.removeAll { $0.weight(at: date) < Self.forgottenWeight }
        if entries.count > Self.maxEntries {
            entries = Array(entries.sorted { $0.weight(at: date) > $1.weight(at: date) }.prefix(Self.maxEntries))
        }
    }

    /// How much each repository's past picks favor it for a term, keyed by the repository's `id`,
    /// taking a term already passed through `FuzzyMatcher.fold`. Picks after typing a longer term
    /// that starts with this one count in proportion to how much of it has been typed, so a
    /// repository picked for exactly this term outranks one picked as often for a longer term.
    func boosts(for term: String, at date: Date) -> [String: Double] {
        guard !term.isEmpty else { return [:] }

        var boosts: [String: Double] = [:]
        for entry in entries where entry.term.hasPrefix(term) {
            let typedShare = Double(term.count) / Double(entry.term.count)
            boosts[entry.repository, default: 0] += entry.weight(at: date) * typedShare
        }
        return boosts
    }
}

extension DashboardOpenHistory {
    private static let defaultsKey = "DashboardOpenHistory"

    /// Kept on this Mac only, since the repositories on it differ from other Macs'.
    init(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let history = try? JSONDecoder().decode(DashboardOpenHistory.self, from: data)
        else {
            return
        }
        self = history
    }

    func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
