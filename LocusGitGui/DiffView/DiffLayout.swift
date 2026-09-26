import Foundation

/// Where everything in a diff goes at one width: each row's top and height, and within a row where
/// the line numbers and the text start. Worked out as arithmetic on a fixed-width font's character
/// width (see `LineWrap`), so a width change on a diff of a hundred thousand rows is one pass over
/// their lengths.
nonisolated struct DiffLayout: Sendable {
    struct Metrics: Equatable, Sendable {
        /// The width of one character of the diff's font.
        var advance: Double
        var lineHeight: Double
        var headerHeight = 32.0
        var hunkHeight = 22.0
        var noticeHeight = 34.0
        var imagesHeight = 280.0
        var margin = 8.0
        var gap = 10.0
    }

    /// One side of a side-by-side diff, or the whole width inline.
    struct Side: Equatable, Sendable {
        let minX: Double
        let maxX: Double
        /// Inline, the old line number and then the new one; side by side, the one for this side.
        let numberXs: [Double]
        let markerX: Double
        let textX: Double
        let textColumns: Int
    }

    /// Each side's text is at least this many columns wide before the diff goes side by side.
    static let sideBySideColumns = 80

    let metrics: Metrics
    let width: Double
    let style: DiffDocument.Style
    let numberColumns: Int
    /// Where the columns go in the diff's own style.
    let sides: [Side]
    /// Where they go in a file laid out inline in a diff that's side by side.
    let inlineSides: [Side]
    private let fileStyles: [DiffDocument.Style]
    /// Each block's top, and after the last, the height of the whole diff.
    let tops: [Double]

    var height: Double {
        tops.last ?? 0
    }

    /// Side by side when both sides have room for a line of the usual length.
    static func style(forWidth width: Double, metrics: Metrics, numberColumns: Int) -> DiffDocument.Style {
        let side = sideGeometry(minX: 0, maxX: width / 2, numbers: 1, numberColumns: numberColumns, metrics: metrics)
        return side.textColumns >= sideBySideColumns ? .sideBySide : .inline
    }

    /// Wide enough for every line number in the diff, and never narrower than three digits.
    static func numberColumns(of files: [DiffFile]) -> Int {
        var largest = 0
        for file in files {
            for hunk in file.patch.hunks {
                largest = max(largest, hunk.oldStart + hunk.lines.count, hunk.newStart + hunk.lines.count)
            }
        }
        return max(3, String(largest).count)
    }

    init(document: DiffDocument, files: [DiffFile], metrics: Metrics, width: Double, numberColumns: Int) {
        self.metrics = metrics
        self.width = width
        style = document.style
        self.numberColumns = numberColumns
        fileStyles = document.fileStyles
        let inlineSides = [Self.sideGeometry(minX: 0, maxX: width, numbers: 2, numberColumns: numberColumns, metrics: metrics)]
        self.inlineSides = inlineSides
        let sides = switch document.style {
        case .inline:
            inlineSides
        case .sideBySide:
            [
                Self.sideGeometry(minX: 0, maxX: (width / 2).rounded(.down), numbers: 1, numberColumns: numberColumns, metrics: metrics),
                Self.sideGeometry(
                    minX: (width / 2).rounded(.down), maxX: width, numbers: 1, numberColumns: numberColumns, metrics: metrics
                ),
            ]
        }
        self.sides = sides
        var tops: [Double] = []
        tops.reserveCapacity(document.blocks.count + 1)
        var top = 0.0
        for block in document.blocks {
            tops.append(top)
            let blockSides = document.fileStyles[block.file] == document.style ? sides : inlineSides
            top += Self.blockHeight(of: block, files: files, sides: blockSides, metrics: metrics)
        }
        tops.append(top)
        self.tops = tops
    }

    private static func sideGeometry(minX: Double, maxX: Double, numbers: Int, numberColumns: Int, metrics: Metrics) -> Side {
        let numberWidth = Double(numberColumns) * metrics.advance
        let numberXs = (0 ..< numbers).map { minX + metrics.margin + Double($0) * (numberWidth + metrics.advance) }
        let markerX = (numberXs.last ?? minX) + numberWidth + metrics.gap
        let textX = markerX + 2 * metrics.advance
        let textColumns = Int(((maxX - metrics.margin - textX) / metrics.advance).rounded(.down))
        return Side(minX: minX, maxX: maxX, numberXs: numberXs, markerX: markerX, textX: textX, textColumns: max(textColumns, 1))
    }

    private static func blockHeight(of block: DiffDocument.Block, files: [DiffFile], sides: [Side], metrics: Metrics) -> Double {
        switch block {
        case .header: metrics.headerHeight
        case .notice: metrics.noticeHeight
        case .images: metrics.imagesHeight
        case .hunk: metrics.hunkHeight
        case let .lines(file, hunk, left, right):
            Double(lineCount(file: files[file], hunk: hunk, left: left, right: right, sides: sides)) * metrics.lineHeight
        }
    }

    private static func lineCount(file: DiffFile, hunk: Int, left: Int?, right: Int?, sides: [Side]) -> Int {
        let lines = file.patch.hunks[hunk].lines
        var count = 1
        if let left {
            count = max(count, visualLines(lines[left], columns: sides[0].textColumns))
        }
        if let right, sides.count > 1 {
            count = max(count, visualLines(lines[right], columns: sides[1].textColumns))
        }
        return count
    }

    static func visualLines(_ line: DiffLine, columns: Int) -> Int {
        if line.columns <= columns {
            return 1
        }
        if line.length > LineWrap.longLine {
            return LineWrap.longLineCount(length: line.length, columns: columns)
        }
        return LineWrap.wrap(Array(line.text.utf16), columns: columns).count
    }

    /// Where the columns go in a file's rows.
    func sides(forFile file: Int) -> [Side] {
        fileStyles.indices.contains(file) && fileStyles[file] != style ? inlineSides : sides
    }

    func top(of block: Int) -> Double {
        tops[block]
    }

    func frame(of block: Int) -> (minY: Double, maxY: Double) {
        (tops[block], tops[block + 1])
    }

    /// The block at a height, or nil past the end.
    func block(atY y: Double) -> Int? {
        guard tops.count > 1, y >= 0, y < height else { return nil }
        var low = 0
        var high = tops.count - 2
        while low < high {
            let middle = (low + high + 1) / 2
            if tops[middle] <= y {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// The blocks that overlap a range of heights.
    func blocks(from minY: Double, to maxY: Double) -> Range<Int> {
        guard let first = block(atY: max(minY, 0)) else { return 0 ..< 0 }
        let last = block(atY: min(maxY, height - 0.001)) ?? tops.count - 2
        return first ..< last + 1
    }
}
