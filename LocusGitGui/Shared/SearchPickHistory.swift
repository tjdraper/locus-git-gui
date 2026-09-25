import Foundation

/// Which items were picked from a search after typing which terms, so the one picked for a term
/// comes first the next time it's typed. Each pick's weight halves every couple of weeks, so recent
/// picks outrank old habits. Ported from Locus Launcher's launch history.
nonisolated struct SearchPickHistory: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let term: String
        let item: String
        var weight: Double
        var updated: Date

        func weight(at date: Date) -> Double {
            weight * pow(0.5, date.timeIntervalSince(updated) / SearchPickHistory.halfLife)
        }
    }

    static let halfLife: TimeInterval = 14 * 24 * 60 * 60
    /// About seven weeks after a single pick.
    private static let forgottenWeight = 0.1
    private static let maxEntries = 1000

    private(set) var entries: [Entry] = []

    /// Takes a term already passed through `FuzzyMatcher.fold`. A pick made with nothing typed has
    /// an empty term, and counts only toward `weights`.
    mutating func record(term: String, item: String, at date: Date) {
        if let index = entries.firstIndex(where: { $0.term == term && $0.item == item }) {
            entries[index].weight = entries[index].weight(at: date) + 1
            entries[index].updated = date
        } else {
            entries.append(Entry(term: term, item: item, weight: 1, updated: date))
        }
        entries.removeAll { $0.weight(at: date) < Self.forgottenWeight }
        if entries.count > Self.maxEntries {
            entries = Array(entries.sorted { $0.weight(at: date) > $1.weight(at: date) }.prefix(Self.maxEntries))
        }
    }

    /// How much each item's past picks favor it for a term, keyed by the item, taking a term already
    /// passed through `FuzzyMatcher.fold`. Picks after typing a longer term that starts with this one
    /// count in proportion to how much of it has been typed, so an item picked for exactly this term
    /// outranks one picked as often for a longer term.
    func boosts(for term: String, at date: Date) -> [String: Double] {
        guard !term.isEmpty else { return [:] }

        var boosts: [String: Double] = [:]
        for entry in entries where entry.term.hasPrefix(term) {
            let typedShare = Double(term.count) / Double(entry.term.count)
            boosts[entry.item, default: 0] += entry.weight(at: date) * typedShare
        }
        return boosts
    }

    /// How recently and often each item has been picked, whatever was typed first.
    func weights(at date: Date) -> [String: Double] {
        var weights: [String: Double] = [:]
        for entry in entries {
            weights[entry.item, default: 0] += entry.weight(at: date)
        }
        return weights
    }
}

extension SearchPickHistory {
    /// Kept on this Mac only, since what's picked from, such as the repositories on it, differs
    /// from other Macs'.
    init(defaults: UserDefaults, key: String) {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(SearchPickHistory.self, from: data)
        else {
            return
        }
        self = history
    }

    func save(to defaults: UserDefaults, key: String) {
        defaults.set(try? JSONEncoder().encode(self), forKey: key)
    }
}
