import Foundation

/// Scores how well a typed query matches one name. The query's letters must appear in the name
/// in order. Letters at the start of words and runs of consecutive letters score higher, so "lgg"
/// finds locus-git-gui and "web" ranks website above names that merely contain those letters.
nonisolated struct FuzzyMatcher: Sendable {
    private static let matchScore = 16
    private static let wordStartBonus = 24
    private static let consecutiveBonus = 24
    private static let gapPenalty = 1
    private static let invalid = Int.min / 4

    /// Folded once up front, because folding every name again on each keystroke is too slow.
    private let characters: [Character]
    private let wordStarts: [Bool]

    init(name: String) {
        var characters: [Character] = []
        var wordStarts: [Bool] = []
        var previous: Character?
        for character in name {
            let folded = Self.foldCharacter(character)
            characters += folded
            wordStarts += folded.indices.map { $0 == 0 && Self.startsWord(character, after: previous) }
            previous = character
        }
        self.characters = characters
        self.wordStarts = wordStarts
    }

    /// The query as it's matched: case, accents and spaces ignored.
    static func fold(_ query: String) -> String {
        String(query.filter { !$0.isWhitespace }.flatMap(foldCharacter))
    }

    private static func foldCharacter(_ character: Character) -> [Character] {
        Array(String(character).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil))
    }

    private static func startsWord(_ character: Character, after previous: Character?) -> Bool {
        guard character.isLetter || character.isNumber else { return false }
        guard let previous else { return true }
        if character.isLetter {
            return !previous.isLetter || (character.isUppercase && previous.isLowercase)
        }
        return !previous.isNumber
    }

    /// Nil when the name doesn't contain the query's letters in order. Takes a query already
    /// passed through `fold`.
    func score(_ query: [Character]) -> Int? {
        guard !query.isEmpty, containsInOrder(query) else { return nil }

        // Finds the best-scoring placement of the query's letters. For each query letter, `match`
        // holds the best score with that letter at each name position, and `best` the best score
        // with it at or before each position, less the gap since.
        let count = characters.count
        var previousMatch = [Int](repeating: Self.invalid, count: count)
        var previousBest = previousMatch
        var match = previousMatch
        var best = previousMatch
        for (queryPosition, queryCharacter) in query.enumerated() {
            for position in 0..<count {
                match[position] = Self.invalid
                if characters[position] == queryCharacter {
                    let bonus = Self.matchScore + (wordStarts[position] ? Self.wordStartBonus : 0)
                    if queryPosition == 0 {
                        match[position] = bonus - position * Self.gapPenalty
                    } else if position > 0 {
                        var previous = previousMatch[position - 1] + Self.consecutiveBonus
                        if position > 1 {
                            previous = max(previous, previousBest[position - 2] - Self.gapPenalty)
                        }
                        if previous > Self.invalid / 2 {
                            match[position] = bonus + previous
                        }
                    }
                }
                best[position] = position > 0 ? max(match[position], best[position - 1] - Self.gapPenalty) : match[position]
            }
            swap(&previousMatch, &match)
            swap(&previousBest, &best)
        }
        let score = previousMatch.max() ?? Self.invalid
        return score > Self.invalid / 2 ? score : nil
    }

    private func containsInOrder(_ query: [Character]) -> Bool {
        var remaining = query[...]
        for character in characters where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty {
                return true
            }
        }
        return false
    }
}
