import Foundation

/// Text selected in a diff. A selection stays on one side of a side-by-side diff, as it would in two
/// documents next to each other, so copying it gives one version of the text.
nonisolated struct DiffSelection: Equatable, Sendable {
    struct Point: Comparable, Sendable {
        var block: Int
        /// A UTF-16 offset into the text of the block's line on the selection's side.
        var offset: Int

        static func < (lhs: Point, rhs: Point) -> Bool {
            (lhs.block, lhs.offset) < (rhs.block, rhs.offset)
        }
    }

    /// 0 for the left side, or the only one inline; 1 for the right.
    var side: Int
    var anchor: Point
    var head: Point

    var start: Point {
        min(anchor, head)
    }

    var end: Point {
        max(anchor, head)
    }

    var isEmpty: Bool {
        anchor == head
    }

    /// The line a block shows on a side, if it shows one there. A file shown inline in a diff that's
    /// side by side has its one line on both, so a selection on either side takes it in.
    static func line(atBlock block: Int, side: Int, document: DiffDocument, files: [DiffFile]) -> DiffLine? {
        guard document.blocks.indices.contains(block),
              case let .lines(file, hunk, left, right) = document.blocks[block],
              let index = side == 0 || document.style(ofBlock: block) == .inline ? left : right else { return nil }
        return files[file].patch.hunks[hunk].lines[index]
    }

    /// The selected part of a block's line, in UTF-16 offsets.
    func range(inBlock block: Int, length: Int) -> Range<Int>? {
        guard block >= start.block, block <= end.block else { return nil }
        let lower = block == start.block ? min(start.offset, length) : 0
        let upper = block == end.block ? min(end.offset, length) : length
        return lower < upper || (lower == upper && block != end.block) ? lower ..< upper : nil
    }

    /// Each line's selected text on its own line. A selection that runs on past the end of a line
    /// takes its line break with it.
    func text(document: DiffDocument, files: [DiffFile]) -> String {
        var parts: [String] = []
        for block in start.block ... end.block {
            guard let line = Self.line(atBlock: block, side: side, document: document, files: files) else { continue }
            let units = Array(line.text.utf16)
            let lower = block == start.block ? min(start.offset, units.count) : 0
            let upper = block == end.block ? min(end.offset, units.count) : units.count
            guard lower <= upper else { continue }
            parts.append(String(utf16CodeUnits: Array(units[lower ..< upper]), count: upper - lower))
        }
        return parts.joined(separator: "\n")
    }
}
