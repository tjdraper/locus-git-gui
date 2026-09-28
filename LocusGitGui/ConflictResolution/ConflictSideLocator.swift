import Foundation

/// Where each conflict sits in one side's whole file, so the pane showing that side can mark it and
/// scroll to it. Git doesn't say, so each side's lines are looked for in the file, in order, each
/// search starting where the last conflict's side was found. A side with no lines, such as one that
/// deleted them, is placed after the lines just before the conflict. Lines repeated nearby can put
/// a mark on the wrong copy; it's a guide for reading, and taking a side uses the result's own text.
nonisolated struct ConflictSideLocator: Sendable {
    enum Side: Sendable {
        case ours
        case base
        case theirs
    }

    /// How many of the lines before a conflict place a side with none of its own.
    private static let placingLines = 3
    /// How far back from a conflict those lines are looked for, so a long stretch with no conflicts
    /// isn't split into lines for every conflict after it.
    private static let placingReach = 4000

    /// Each of the file's lines as a hash of its bytes, which is much quicker to index than the
    /// lines as strings. Lines are matched by hash alone: two different lines sharing a 64-bit hash
    /// would only misplace a mark.
    private let lines: [UInt64]
    /// Where each hash is among the lines, so a search starts from the side's rarest line rather
    /// than reading the file from the top for every conflict.
    private let positions: [UInt64: [Int]]
    /// Where each of the file's lines starts, with the file's end last.
    let lineStarts: [Int]

    init(file: String) {
        let (lines, starts) = Self.scan(file, recordingStarts: true)
        var positions: [UInt64: [Int]] = [:]
        for (number, line) in lines.enumerated() {
            positions[line, default: []].append(number)
        }
        self.lines = lines
        self.positions = positions
        lineStarts = starts
    }

    /// A range of the file's lines for each conflict, empty where the side has no lines or they
    /// weren't found. Nil for a conflict whose side isn't in `result`, such as the ancestor when Git
    /// didn't write it.
    func locate(_ side: Side, of markers: ConflictMarkers, in result: String) -> [Range<Int>?] {
        let text = result as NSString
        var anchor = 0
        var previousEnd = 0
        var located: [Range<Int>?] = []
        for conflict in markers.conflicts {
            defer { previousEnd = NSMaxRange(conflict.range) }
            let sideRange: NSRange? = switch side {
            case .ours: conflict.ours
            case .base: conflict.base
            case .theirs: conflict.theirs
            }
            guard let sideRange else {
                located.append(nil)
                continue
            }
            let sideLines = Self.scan(text.substring(with: sideRange), recordingStarts: false).lines
            if let start = find(sideLines, from: anchor) {
                anchor = start + sideLines.count
                located.append(start ..< anchor)
                continue
            }
            let beforeStart = max(previousEnd, conflict.range.location - Self.placingReach)
            let before = text.substring(with: NSRange(location: beforeStart, length: conflict.range.location - beforeStart))
            let placing = Array(Self.scan(before, recordingStarts: false).lines.suffix(Self.placingLines))
            if !placing.isEmpty, let start = find(placing, from: anchor) {
                anchor = start + placing.count
            }
            located.append(anchor ..< anchor)
        }
        return located
    }

    /// The characters of a range of lines, as a text view counts them.
    func characters(of range: Range<Int>) -> NSRange {
        let last = lineStarts.count - 1
        let start = lineStarts[min(range.lowerBound, last)]
        let end = lineStarts[min(range.upperBound, last)]
        return NSRange(location: start, length: end - start)
    }

    /// Where each line starts, counted in UTF-16 code units as a text view counts, with the text's
    /// end last.
    static func lineStarts(of text: String) -> [Int] {
        scan(text, recordingStarts: true).starts
    }

    private func find(_ wanted: [UInt64], from anchor: Int) -> Int? {
        guard !wanted.isEmpty else { return nil }
        var rarest = 0
        for offset in wanted.indices where (positions[wanted[offset]]?.count ?? 0) < (positions[wanted[rarest]]?.count ?? 0) {
            rarest = offset
        }
        guard let candidates = positions[wanted[rarest]] else { return nil }
        var low = 0
        var high = candidates.count
        while low < high {
            let middle = (low + high) / 2
            if candidates[middle] - rarest < anchor {
                low = middle + 1
            } else {
                high = middle
            }
        }
        for position in candidates[low...] {
            let start = position - rarest
            guard start + wanted.count <= lines.count else { return nil }
            if lines[start ..< start + wanted.count].elementsEqual(wanted) {
                return start
            }
        }
        return nil
    }

    /// Each line's FNV-1a hash, leaving out its ending and a carriage return before it, so a file
    /// whose line endings Git changed on checkout still matches. UTF-16 offsets are counted from the
    /// UTF-8 bytes as they go: a byte that starts a character counts one, and a four-byte one two.
    private static func scan(_ text: String, recordingStarts: Bool) -> (lines: [UInt64], starts: [Int]) {
        let basis: UInt64 = 0xCBF2_9CE4_8422_2325
        let prime: UInt64 = 0x100_0000_01B3
        var lines: [UInt64] = []
        var starts = [0]
        var hash = basis
        var offset = 0
        var isLineEmpty = true
        var heldReturn = false
        for byte in text.utf8 {
            if recordingStarts {
                if byte < 0x80 || byte >= 0xC0 {
                    offset += byte >= 0xF0 ? 2 : 1
                }
            }
            if byte == 0x0A {
                lines.append(hash)
                hash = basis
                isLineEmpty = true
                heldReturn = false
                if recordingStarts {
                    starts.append(offset)
                }
                continue
            }
            if heldReturn {
                hash = (hash ^ 0x0D) &* prime
                heldReturn = false
            }
            isLineEmpty = false
            if byte == 0x0D {
                heldReturn = true
            } else {
                hash = (hash ^ UInt64(byte)) &* prime
            }
        }
        if !isLineEmpty {
            if heldReturn {
                hash = (hash ^ 0x0D) &* prime
            }
            lines.append(hash)
            if recordingStarts {
                starts.append(offset)
            }
        }
        return (lines, starts)
    }
}
