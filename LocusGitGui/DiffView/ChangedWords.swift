import Foundation

/// The parts of a changed line that differ from the line it replaced, so they can be marked inside
/// lines that are otherwise the same. Compared a word at a time rather than a character at a time,
/// which marks `count` → `total` as one change rather than as the letters that happen to differ.
nonisolated enum ChangedWords {
    /// Ranges are in UTF-16 offsets into each line's text.
    struct Ranges: Equatable, Sendable {
        let old: [Range<Int>]
        let new: [Range<Int>]
    }

    /// Past this many token pairs, lines are compared by their common start and end alone, which
    /// keeps a pair of enormous lines from taking seconds.
    private static let comparisonLimit = 40000
    /// Two lines that share less than this much of the shorter one's text, or of the longer one's,
    /// are different lines rather than one line changed, and marking nearly all of both says
    /// nothing. The longer one's is lower, so text added to a line is still marked.
    private static let minimumSharedOfShorter = 0.5
    private static let minimumSharedOfLonger = 0.25

    /// Nil when there's nothing worth marking: the lines are the same, have too little in common,
    /// or are too long to be read as lines, such as a minified file's.
    static func compare(_ old: String, _ new: String) -> Ranges? {
        guard old.utf16.count <= LineWrap.longLine, new.utf16.count <= LineWrap.longLine else { return nil }
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)
        guard oldUnits != newUnits else { return nil }
        let oldTokens = tokens(oldUnits)
        let newTokens = tokens(newUnits)
        let (oldKept, newKept) = oldTokens.count * newTokens.count <= comparisonLimit
            ? commonTokens(oldTokens, newTokens, oldUnits, newUnits)
            : commonEnds(oldTokens, newTokens, oldUnits, newUnits)
        let sharedLength = oldTokens.indices.filter { oldKept[$0] && !isSpace(oldTokens[$0], oldUnits) }
            .reduce(0) { $0 + oldTokens[$1].count }
        let lengths = [visibleLength(oldTokens, oldUnits), visibleLength(newTokens, newUnits)]
        guard let shortest = lengths.min(), let longest = lengths.max(), shortest > 0,
              Double(sharedLength) >= Double(shortest) * minimumSharedOfShorter,
              Double(sharedLength) >= Double(longest) * minimumSharedOfLonger else { return nil }
        return Ranges(
            old: changedRanges(oldTokens, kept: oldKept, oldUnits),
            new: changedRanges(newTokens, kept: newKept, newUnits)
        )
    }

    /// Runs of letters and digits, runs of spaces, and each other character on its own.
    static func tokens(_ units: [UInt16]) -> [Range<Int>] {
        var tokens: [Range<Int>] = []
        var index = 0
        while index < units.count {
            let start = index
            let kind = kind(of: units[index])
            index += 1
            if kind != .symbol {
                while index < units.count, self.kind(of: units[index]) == kind {
                    index += 1
                }
            } else if UTF16.isLeadSurrogate(units[start]), index < units.count, UTF16.isTrailSurrogate(units[index]) {
                index += 1
            }
            tokens.append(start ..< index)
        }
        return tokens
    }

    private enum TokenKind {
        case word
        case space
        case symbol
    }

    /// Any character beyond ASCII counts as part of a word, which keeps accented and non-Latin words
    /// whole.
    private static func kind(of unit: UInt16) -> TokenKind {
        switch unit {
        case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A, 0x5F: .word
        case 0x20, 0x09: .space
        case 0x80...: UTF16.isLeadSurrogate(unit) || UTF16.isTrailSurrogate(unit) ? .symbol : .word
        default: .symbol
        }
    }

    private static func isSpace(_ token: Range<Int>, _ units: [UInt16]) -> Bool {
        kind(of: units[token.lowerBound]) == .space
    }

    private static func visibleLength(_ tokens: [Range<Int>], _ units: [UInt16]) -> Int {
        tokens.reduce(0) { $0 + (isSpace($1, units) ? 0 : $1.count) }
    }

    private static func same(_ old: Range<Int>, _ new: Range<Int>, _ oldUnits: [UInt16], _ newUnits: [UInt16]) -> Bool {
        old.count == new.count && oldUnits[old].elementsEqual(newUnits[new])
    }

    /// The longest common subsequence of tokens: which tokens on each side are kept.
    private static func commonTokens(
        _ old: [Range<Int>],
        _ new: [Range<Int>],
        _ oldUnits: [UInt16],
        _ newUnits: [UInt16]
    ) -> ([Bool], [Bool]) {
        let width = new.count + 1
        var lengths = [Int](repeating: 0, count: (old.count + 1) * width)
        for oldIndex in stride(from: old.count - 1, through: 0, by: -1) {
            for newIndex in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[oldIndex * width + newIndex] = same(old[oldIndex], new[newIndex], oldUnits, newUnits)
                    ? lengths[(oldIndex + 1) * width + newIndex + 1] + 1
                    : max(lengths[(oldIndex + 1) * width + newIndex], lengths[oldIndex * width + newIndex + 1])
            }
        }
        var oldKept = [Bool](repeating: false, count: old.count)
        var newKept = [Bool](repeating: false, count: new.count)
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count, newIndex < new.count {
            if same(old[oldIndex], new[newIndex], oldUnits, newUnits) {
                oldKept[oldIndex] = true
                newKept[newIndex] = true
                oldIndex += 1
                newIndex += 1
            } else if lengths[(oldIndex + 1) * width + newIndex] >= lengths[oldIndex * width + newIndex + 1] {
                oldIndex += 1
            } else {
                newIndex += 1
            }
        }
        return (oldKept, newKept)
    }

    private static func commonEnds(
        _ old: [Range<Int>],
        _ new: [Range<Int>],
        _ oldUnits: [UInt16],
        _ newUnits: [UInt16]
    ) -> ([Bool], [Bool]) {
        var oldKept = [Bool](repeating: false, count: old.count)
        var newKept = [Bool](repeating: false, count: new.count)
        var prefix = 0
        while prefix < min(old.count, new.count), same(old[prefix], new[prefix], oldUnits, newUnits) {
            oldKept[prefix] = true
            newKept[prefix] = true
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              same(old[old.count - 1 - suffix], new[new.count - 1 - suffix], oldUnits, newUnits) {
            oldKept[old.count - 1 - suffix] = true
            newKept[new.count - 1 - suffix] = true
            suffix += 1
        }
        return (oldKept, newKept)
    }

    /// Changed tokens next to each other, or with only spaces between them, make one range.
    private static func changedRanges(_ tokens: [Range<Int>], kept: [Bool], _ units: [UInt16]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for (index, token) in tokens.enumerated() where !kept[index] {
            if let last = ranges.last, units[last.upperBound ..< token.lowerBound].allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
                ranges[ranges.count - 1] = last.lowerBound ..< token.upperBound
            } else {
                ranges.append(token)
            }
        }
        return ranges
    }
}
