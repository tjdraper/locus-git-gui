import Foundation

/// A palette step's items prepared for searching, built once per step rather than on every
/// keystroke.
nonisolated struct CommandPaletteSearch {
    let items: [CommandPaletteItem]
    private let matchers: [FuzzyMatcher]

    init(items: [CommandPaletteItem]) {
        self.items = items
        matchers = items.map { FuzzyMatcher(name: $0.title) }
    }

    /// The positions in `items` to show, best first. With nothing typed, the items picked most
    /// recently and often come first and the rest keep their order. Once something is typed, items
    /// picked for that search before come first, then the best matches, and equal matches keep their
    /// order.
    func rank(_ query: String, history: SearchPickHistory, at date: Date) -> [Int] {
        let term = FuzzyMatcher.fold(query)
        guard !term.isEmpty else {
            let weights = history.weights(at: date)
            let listed = items.indices.filter { items[$0].isListedBeforeTyping }
            return listed.enumerated()
                .sorted { lhs, rhs in
                    let lhsWeight = weights[items[lhs.element].id] ?? 0
                    let rhsWeight = weights[items[rhs.element].id] ?? 0
                    return lhsWeight != rhsWeight ? lhsWeight > rhsWeight : lhs.offset < rhs.offset
                }
                .map(\.element)
        }

        struct Match {
            let position: Int
            let boost: Double
            let score: Int
        }
        let boosts = history.boosts(for: term, at: date)
        let characters = Array(term)
        return items.indices
            .compactMap { position -> Match? in
                guard let score = matchers[position].score(characters) else { return nil }
                return Match(position: position, boost: boosts[items[position].id] ?? 0, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.boost != rhs.boost {
                    return lhs.boost > rhs.boost
                }
                return lhs.score != rhs.score ? lhs.score > rhs.score : lhs.position < rhs.position
            }
            .map(\.position)
    }
}
