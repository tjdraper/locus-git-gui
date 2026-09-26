import AppKit

/// Draws a diff's hunk bands and lines, one row at a time, where `DiffLayout` put them. Each visual
/// line is typeset on its own as it's drawn, so only what's on screen is ever laid out.
struct DiffRowPainter {
    /// Where the text of one side of a row wrapped, kept for the lines that wrap, since finding the
    /// breaks means reading the whole line.
    struct Wrapped {
        let units: [UInt16]
        let lines: LineWrap.Lines
    }

    let font: NSFont
    let metrics: DiffLayout.Metrics
    private let textAttributes: [NSAttributedString.Key: Any]
    private let numberAttributes: [NSAttributedString.Key: Any]
    private let sectionAttributes: [NSAttributedString.Key: Any]
    private let noteAttributes: [NSAttributedString.Key: Any]
    /// Starts each line a long line wraps onto.
    private let wrapMarkerAttributes: [NSAttributedString.Key: Any]

    init(font: NSFont, metrics: DiffLayout.Metrics) {
        self.font = font
        self.metrics = metrics
        let paragraph = NSMutableParagraphStyle()
        paragraph.defaultTabInterval = metrics.advance * Double(LineWrap.tabWidth)
        paragraph.tabStops = []
        textAttributes = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        numberAttributes = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        sectionAttributes = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        wrapMarkerAttributes = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        noteAttributes = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
    }

    /// The font's own line height is less than a row's, and the text sits in the middle.
    private var textInset: Double {
        ((metrics.lineHeight - (font.ascender - font.descender + font.leading)) / 2).rounded(.down)
    }

    func drawHunk(_ hunk: DiffHunk, in rect: NSRect) {
        NSColor.quaternarySystemFill.setFill()
        rect.fill()
        guard !hunk.section.isEmpty else { return }
        let line = typeset(hunk.section, attributes: sectionAttributes)
        let baseline = rect.minY + (rect.height - (font.ascender - font.descender)) / 2 + font.ascender
        draw(line, at: NSPoint(x: rect.minX + metrics.margin, y: baseline), clippedTo: rect)
    }

    /// One side of a row as it's drawn.
    private struct SideContent {
        let line: DiffLine
        let text: Wrapped
        let selected: Range<Int>?
        /// Inline, the old and new line numbers; side by side, the one for this side.
        let numbers: [Int?]
    }

    private struct Colors {
        let row: NSColor?
        let words: NSColor?
        let marker: (text: String, color: NSColor)?
    }

    /// How the canvas that draws a row wraps its text and what it has selected.
    struct RowState {
        let wrapped: (_ side: Int, _ line: DiffLine) -> Wrapped
        let selection: (_ side: Int, _ length: Int) -> Range<Int>?
        let isFocused: Bool
    }

    /// Where a row's columns go. One side is inline, and two are side by side.
    struct Columns {
        let sides: [DiffLayout.Side]
        let numberColumns: Int
    }

    func drawLines(left: DiffLine?, right: DiffLine?, in rect: NSRect, columns: Columns, state: RowState) {
        let sides = columns.sides
        let numberColumns = columns.numberColumns
        let isFocused = state.isFocused
        func content(_ line: DiffLine, side: Int, numbers: [Int?]) -> SideContent {
            let text = state.wrapped(side, line)
            return SideContent(line: line, text: text, selected: state.selection(side, text.units.count), numbers: numbers)
        }
        if sides.count == 1 {
            guard let left else { return }
            let side = content(left, side: 0, numbers: [left.oldNumber, left.newNumber])
            draw(side, geometry: sides[0], numberColumns: numberColumns, in: rect, isFocused: isFocused)
            return
        }
        for (index, line) in [left, right].enumerated() {
            let geometry = sides[index]
            let sideRect = NSRect(x: geometry.minX, y: rect.minY, width: geometry.maxX - geometry.minX, height: rect.height)
            if let line {
                let side = content(line, side: index, numbers: [index == 0 ? line.oldNumber : line.newNumber])
                draw(side, geometry: geometry, numberColumns: numberColumns, in: sideRect, isFocused: isFocused)
            } else {
                NSColor.quaternarySystemFill.setFill()
                sideRect.fill()
            }
        }
        NSColor.separatorColor.setFill()
        NSRect(x: sides[1].minX, y: rect.minY, width: 1, height: rect.height).fill()
    }

    private func draw(_ content: SideContent, geometry side: DiffLayout.Side, numberColumns: Int, in rect: NSRect, isFocused: Bool) {
        let line = content.line
        let colors = Self.colors(for: line.kind)
        if let tint = colors.row {
            tint.setFill()
            rect.fill()
        }
        let baseline = rect.minY + textInset + font.ascender
        for (numberX, number) in zip(side.numberXs, content.numbers) {
            guard let number else { continue }
            let text = String(number)
            let x = numberX + Double(max(numberColumns - text.count, 0)) * metrics.advance
            draw(typeset(text, attributes: numberAttributes), at: NSPoint(x: x, y: baseline), clippedTo: rect)
        }
        if let marker = colors.marker {
            let markerLine = typeset(marker.text, attributes: [.font: font, .foregroundColor: marker.color])
            draw(markerLine, at: NSPoint(x: side.markerX, y: baseline), clippedTo: rect)
        }

        let text = content.text
        let selectedRange = content.selected
        let clip = NSRect(x: side.textX, y: rect.minY, width: max(side.maxX - side.textX, 0), height: rect.height)
        for (index, range) in text.lines.ranges(length: text.units.count).enumerated() {
            let lineTop = rect.minY + Double(index) * metrics.lineHeight
            let x = side.textX + Double(text.lines.textColumn(ofLine: index)) * metrics.advance
            if index > 0 {
                let markerX = side.textX + Double(text.lines.indent) * metrics.advance
                let marker = typeset("↳", attributes: wrapMarkerAttributes)
                draw(marker, at: NSPoint(x: markerX, y: lineTop + textInset + font.ascender), clippedTo: clip)
            }
            let segment = typesetText(String(decoding: text.units[range], as: UTF16.self))
            let lineRect = NSRect(x: x, y: lineTop, width: clip.maxX - x, height: metrics.lineHeight)
            if let wordTint = colors.words {
                wordTint.setFill()
                for word in line.changedWords {
                    highlight(word, in: range, of: segment, x: x, rect: lineRect)
                }
            }
            if let selectedRange {
                (isFocused ? NSColor.selectedTextBackgroundColor : NSColor.unemphasizedSelectedTextBackgroundColor).setFill()
                highlight(selectedRange, in: range, of: segment, x: x, rect: lineRect, includesLineEnd: index == text.lines.count - 1)
            }
            draw(segment, at: NSPoint(x: x, y: lineTop + textInset + font.ascender), clippedTo: clip)
            if index == text.lines.count - 1, line.hasNoNewlineAtEnd {
                drawNoNewlineNote(after: x + CTLineGetTypographicBounds(segment, nil, nil, nil), top: lineTop, clip: clip)
            }
        }
    }

    /// Fills behind the part of `highlighted` that falls on this visual line. An empty selection at
    /// the end of a line still marks where the line ends, so a selected blank line shows.
    private func highlight(
        _ highlighted: Range<Int>,
        in range: Range<Int>,
        of segment: CTLine,
        x: Double,
        rect: NSRect,
        includesLineEnd: Bool = false
    ) {
        let lower = max(highlighted.lowerBound, range.lowerBound)
        let upper = min(highlighted.upperBound, range.upperBound)
        if lower < upper {
            let start = CTLineGetOffsetForStringIndex(segment, lower - range.lowerBound, nil)
            let end = CTLineGetOffsetForStringIndex(segment, upper - range.lowerBound, nil)
            NSRect(x: x + start, y: rect.minY, width: end - start, height: rect.height).fill()
        } else if includesLineEnd, highlighted.isEmpty, highlighted.lowerBound == range.upperBound {
            let start = CTLineGetOffsetForStringIndex(segment, range.count, nil)
            NSRect(x: x + start, y: rect.minY, width: metrics.advance / 2, height: rect.height).fill()
        }
    }

    private func drawNoNewlineNote(after x: Double, top: Double, clip: NSRect) {
        let note = typeset("No newline at end of file", attributes: noteAttributes)
        let noteFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let baseline = top + (metrics.lineHeight - (noteFont.ascender - noteFont.descender)) / 2 + noteFont.ascender
        draw(note, at: NSPoint(x: x + metrics.advance * 2, y: baseline), clippedTo: clip)
    }

    /// System colours, which adjust themselves for dark mode, over the text background.
    private static func colors(for kind: DiffLine.Kind) -> Colors {
        switch kind {
        case .context:
            Colors(row: nil, words: nil, marker: nil)
        case .added:
            Colors(
                row: NSColor.systemGreen.withAlphaComponent(0.14),
                words: NSColor.systemGreen.withAlphaComponent(0.32),
                marker: ("+", NSColor.systemGreen)
            )
        case .removed:
            Colors(
                row: NSColor.systemRed.withAlphaComponent(0.14),
                words: NSColor.systemRed.withAlphaComponent(0.32),
                marker: ("−", NSColor.systemRed)
            )
        }
    }

    /// A line's text as it's drawn, so a point in it can be found the same way.
    func typesetText(_ text: String) -> CTLine {
        typeset(text, attributes: textAttributes)
    }

    func typeset(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// Core Text draws upward from the baseline, so the text matrix flips it back in a flipped view.
    private func draw(_ line: CTLine, at point: NSPoint, clippedTo clip: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: clip)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
