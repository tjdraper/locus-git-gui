import Foundation

/// The conflicts Git wrote into a file, found by their marker lines: `<<<<<<<` before the checked-out
/// side, `|||||||` before the common ancestor when `merge.conflictStyle` is `diff3` or `zdiff3`,
/// `=======` before the side being brought in, and `>>>>>>>` after it. The file is read as it is on
/// disk rather than merged again, so edits made elsewhere, and conflicts `git rerere` already
/// resolved, are kept.
nonisolated struct ConflictMarkers: Equatable, Sendable {
    /// Ranges count UTF-16 code units, as a text view does. Each side's range takes in its lines'
    /// endings, so taking a side is replacing `range` with that side's text.
    struct Conflict: Equatable, Sendable {
        /// From the start of the first marker line to the end of the last, its line ending included.
        let range: NSRange
        let ours: NSRange
        let base: NSRange?
        let theirs: NSRange
        /// What Git wrote after the markers, such as the branch being merged in.
        let oursLabel: String
        let theirsLabel: String
    }

    enum Choice: Equatable, Sendable {
        case ours
        case theirs
        case oursThenTheirs
    }

    /// Git's own size, unless a `conflict-marker-size` attribute sets another for the file.
    static let defaultMarkerSize = 7

    let conflicts: [Conflict]

    private enum Section {
        case outside
        case ours(start: Int, oursStart: Int, label: String)
        case base(start: Int, oursStart: Int, oursEnd: Int, baseStart: Int, label: String)
        case theirs(start: Int, ours: NSRange, base: NSRange?, theirsStart: Int, label: String)
    }

    /// A conflict with no closing marker is left out, since it isn't one Git wrote.
    init(parsing text: String, markerSize: Int = Self.defaultMarkerSize) {
        let units = Array(text.utf16)
        var conflicts: [Conflict] = []
        var section = Section.outside
        var lineStart = 0
        while lineStart < units.count {
            let newline = units[lineStart...].firstIndex(of: 0x0A)
            let lineEnd = newline ?? units.count
            let nextLine = newline.map { $0 + 1 } ?? units.count
            let line = units[lineStart ..< lineEnd]
            let marker = Self.marker(in: line, size: markerSize)
            switch (section, marker) {
            case (_, .opening(let label)):
                section = .ours(start: lineStart, oursStart: nextLine, label: label)
            case let (.ours(start, oursStart, label), .ancestor):
                section = .base(start: start, oursStart: oursStart, oursEnd: lineStart, baseStart: nextLine, label: label)
            case let (.ours(start, oursStart, label), .separator):
                section = .theirs(start: start, ours: Self.range(oursStart, lineStart), base: nil, theirsStart: nextLine, label: label)
            case let (.base(start, oursStart, oursEnd, baseStart, label), .separator):
                let ours = Self.range(oursStart, oursEnd)
                section = .theirs(start: start, ours: ours, base: Self.range(baseStart, lineStart), theirsStart: nextLine, label: label)
            case (.theirs(let start, let ours, let base, let theirsStart, let oursLabel), .closing(let theirsLabel)):
                conflicts.append(Conflict(
                    range: Self.range(start, nextLine),
                    ours: ours,
                    base: base,
                    theirs: Self.range(theirsStart, lineStart),
                    oursLabel: oursLabel,
                    theirsLabel: theirsLabel
                ))
                section = .outside
            default:
                break
            }
            lineStart = nextLine
        }
        self.conflicts = conflicts
    }

    private enum Marker {
        case opening(label: String)
        case ancestor
        case separator
        case closing(label: String)
    }

    /// A marker is the character repeated exactly `size` times at the start of the line, followed by
    /// a space and a label, or by nothing but the line's ending. The separator never has a label.
    private static func marker(in line: ArraySlice<UInt16>, size: Int) -> Marker? {
        guard line.count >= size, let first = line.first else { return nil }
        let characters: [UInt16: Character] = [0x3C: "<", 0x7C: "|", 0x3D: "=", 0x3E: ">"]
        guard let character = characters[first], line.prefix(size).allSatisfy({ $0 == first }) else { return nil }
        var rest = line.dropFirst(size)
        if rest.last == 0x0D {
            rest = rest.dropLast()
        }
        let label: String
        if rest.isEmpty {
            label = ""
        } else if rest.first == 0x20, character != "=" {
            label = String(decoding: rest.dropFirst(), as: UTF16.self)
        } else {
            return nil
        }
        switch character {
        case "<": return .opening(label: label)
        case "|": return .ancestor
        case "=": return .separator
        default: return .closing(label: label)
        }
    }

    private static func range(_ start: Int, _ end: Int) -> NSRange {
        NSRange(location: start, length: end - start)
    }

    /// The conflict `location` falls in, such as where the cursor is.
    func index(containing location: Int) -> Int? {
        conflicts.firstIndex { NSLocationInRange(location, $0.range) }
    }

    /// What replaces the conflict in `text` to take a side.
    static func resolution(of conflict: Conflict, in text: NSString, choosing choice: Choice) -> String {
        switch choice {
        case .ours: text.substring(with: conflict.ours)
        case .theirs: text.substring(with: conflict.theirs)
        case .oursThenTheirs: text.substring(with: conflict.ours) + text.substring(with: conflict.theirs)
        }
    }
}
