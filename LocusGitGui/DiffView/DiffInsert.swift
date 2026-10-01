import Foundation

/// Something whoever shows a diff puts into it, below a line or at the top of a file, such as a
/// thread of comments. The diff leaves room for it and lays its view there; what it shows is up
/// to them.
nonisolated struct DiffInsert: Equatable, Sendable {
    enum Side: Equatable, Sendable {
        /// Where removed lines are.
        case old
        case new
    }

    enum Place: Equatable, Sendable {
        /// Below the file's header and anything said about the file, above its first hunk.
        case top
        /// Below the row showing this line, counted from 1 on that side. A line the diff doesn't
        /// show puts it below the nearest one before it that it does.
        case line(Side, Int)
    }

    let id: String
    let file: DiffFile.Identity
    let place: Place
}

/// Lines picked on one side of a file, for whoever shows the diff to act on, such as commenting
/// on them.
nonisolated struct DiffLineTarget: Equatable, Sendable {
    let file: DiffFile.Identity
    let side: DiffInsert.Side
    /// Counted from 1, on that side.
    let lines: ClosedRange<Int>
    let text: [String]
}

nonisolated extension DiffLineTarget {
    /// The lines rows show on one side of the diff, for a selection or a right-click. Inline, a
    /// removed line is on the old side and any other on the new, so a selection that takes in both
    /// is on the new side. Nil when the rows show no lines, or lines of more than one file.
    init?(blocks: ClosedRange<Int>, side: Int, document: DiffDocument, files: [DiffFile]) {
        struct Shown {
            let file: Int
            let line: DiffLine
            let isInline: Bool
        }
        var shown: [Shown] = []
        for block in blocks where document.blocks.indices.contains(block) {
            guard let line = DiffSelection.line(atBlock: block, side: side, document: document, files: files) else { continue }
            shown.append(Shown(file: document.blocks[block].file, line: line, isInline: document.style(ofBlock: block) == .inline))
        }
        guard let first = shown.first, shown.allSatisfy({ $0.file == first.file }) else { return nil }
        let targetSide: DiffInsert.Side = if first.isInline {
            shown.contains { $0.line.newNumber != nil } ? .new : .old
        } else {
            side == 0 ? .old : .new
        }
        let numbered = shown.compactMap { entry -> (number: Int, text: String)? in
            let number = targetSide == .old ? entry.line.oldNumber : entry.line.newNumber
            return number.map { ($0, entry.line.text) }
        }
        guard let low = numbered.map(\.number).min(), let high = numbered.map(\.number).max() else { return nil }
        self.init(file: files[first.file].id, side: targetSide, lines: low ... high, text: numbered.map(\.text))
    }
}
