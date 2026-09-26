import Foundation

/// Where a line of a diff wraps to fit its column, worked out from character widths in a fixed-width
/// font rather than by laying out the text. That makes the height of every row known without laying
/// out any of them, so a diff of a hundred thousand lines, or one line of a million characters, is
/// as quick to scroll through as a short one.
nonisolated enum LineWrap {
    static let tabWidth = 4
    /// Past this many UTF-16 units, such as a minified file's one line, a line breaks every so many
    /// characters rather than between words. Its height is then known from its length alone, so a
    /// line of millions of characters costs nothing to lay out.
    static let longLine = 10000

    /// Each line a line wraps onto starts with a marker, and a space after it, so it can't be
    /// mistaken for a line of its own.
    static let markerColumns = 2

    /// How many lines a line of this length wraps to past `longLine`.
    static func longLineCount(length: Int, columns: Int) -> Int {
        let columns = max(columns, 1)
        guard length > columns else { return 1 }
        let continuation = max(columns - markerColumns, 1)
        return 1 + (length - columns + continuation - 1) / continuation
    }

    struct Lines: Equatable, Sendable {
        /// The UTF-16 offset each line after the first starts at.
        let breaks: [Int]
        /// How far in columns the marker on each line after the first sits, which lines it up
        /// with the indentation of the first line.
        let indent: Int

        var count: Int {
            breaks.count + 1
        }

        /// The column a visual line's text starts at: the first at the start, and the rest after
        /// their marker.
        func textColumn(ofLine index: Int) -> Int {
            index == 0 ? 0 : indent + markerColumns
        }

        /// The UTF-16 offsets of each line.
        func ranges(length: Int) -> [Range<Int>] {
            let starts = [0] + breaks
            return starts.indices.map { index in
                starts[index] ..< (index + 1 < starts.count ? starts[index + 1] : length)
            }
        }
    }

    /// How many columns the text takes on one line.
    static func width(of units: some Collection<UInt16>) -> Int {
        var column = 0
        for unit in units {
            column += width(of: unit, at: column)
        }
        return column
    }

    /// Breaks after a space where it can, and within a word only when the word is wider than the
    /// line. Continuation lines are indented as far as the first line's leading spaces, up to half
    /// the line, and then past their marker.
    static func wrap(_ units: [UInt16], columns: Int) -> Lines {
        let columns = max(columns, markerColumns + 1)
        guard units.count <= longLine else {
            let first = [columns]
            let rest = stride(from: columns + columns - markerColumns, to: units.count, by: columns - markerColumns)
            let breaks = (first + rest).filter { $0 < units.count }.map { UTF16.isTrailSurrogate(units[$0]) ? $0 - 1 : $0 }
            return Lines(breaks: breaks, indent: 0)
        }
        var indent = 0
        for unit in units {
            guard unit == 0x20 || unit == 0x09 else { break }
            indent += width(of: unit, at: indent)
        }
        indent = indent + markerColumns <= columns / 2 ? indent : 0

        var breaks: [Int] = []
        var lineStart = 0
        var column = 0
        var breakOpportunity: Int?
        var index = 0
        while index < units.count {
            let unit = units[index]
            let unitWidth = width(of: unit, at: column)
            if column + unitWidth > columns, index > lineStart {
                var breakAt = breakOpportunity ?? index
                if breakAt == index, UTF16.isTrailSurrogate(unit), index - 1 > lineStart {
                    breakAt = index - 1
                }
                breaks.append(breakAt)
                lineStart = breakAt
                column = indent + markerColumns
                breakOpportunity = nil
                index = breakAt
                continue
            }
            column += unitWidth
            index += 1
            if unit == 0x20 || unit == 0x09, index < units.count {
                breakOpportunity = index
            }
        }
        return Lines(breaks: breaks, indent: indent)
    }

    /// Wide East Asian characters and emoji take two columns, and combining marks none.
    static func width(of unit: UInt16, at column: Int) -> Int {
        switch unit {
        case 0x09: tabWidth - column % tabWidth
        case 0x0300 ... 0x036F, 0x200B ... 0x200F, 0xFE00 ... 0xFE0F: 0
        case 0xDC00 ... 0xDFFF: 0
        case 0xD800 ... 0xDBFF: 2
        case 0x1100 ... 0x115F, 0x2E80 ... 0xA4CF, 0xAC00 ... 0xD7A3, 0xF900 ... 0xFAFF, 0xFE30 ... 0xFE4F, 0xFF00 ... 0xFF60,
             0xFFE0 ... 0xFFE6:
            2
        default: 1
        }
    }
}
