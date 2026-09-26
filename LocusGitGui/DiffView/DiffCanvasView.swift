import AppKit

/// The diff's scrolling surface. It draws the hunks and lines on screen and nothing else; file
/// headers, notices and images are views laid over it (see `DiffBlockViews`). Text is selected and
/// copied here, a side at a time.
final class DiffCanvasView: NSView {
    struct Content {
        let files: [DiffFile]
        let document: DiffDocument
        let layout: DiffLayout
        let painter: DiffRowPainter
    }

    var onSelectionChange: (() -> Void)?
    var makeMenu: ((_ file: Int?) -> NSMenu?)?
    var onFocusChange: (() -> Void)?
    /// A key typed while the diff has focus, which has no text to type into. True when it was used.
    var onTypedKey: ((String) -> Bool)?

    private(set) var content: Content?
    private(set) var selection: DiffSelection?
    /// Lines that wrap, as last wrapped, so a long line isn't read again every time it's drawn.
    private var wrapCache: [WrapKey: DiffRowPainter.Wrapped] = [:]

    private struct WrapKey: Hashable {
        let block: Int
        let side: Int
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        content != nil
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        onFocusChange?()
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        onFocusChange?()
        return true
    }

    private var isFocused: Bool {
        window?.firstResponder === self && window?.isKeyWindow == true
    }

    func show(_ content: Content?, keepingSelection: Bool) {
        self.content = content
        wrapCache = [:]
        if !keepingSelection {
            selection = nil
        }
        needsDisplay = true
    }

    func clearSelection() {
        guard selection != nil else { return }
        selection = nil
        needsDisplay = true
        onSelectionChange?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        guard let content else { return }
        let layout = content.layout
        for block in layout.blocks(from: dirtyRect.minY, to: dirtyRect.maxY) {
            let frame = layout.frame(of: block)
            let rect = NSRect(x: 0, y: frame.minY, width: bounds.width, height: frame.maxY - frame.minY)
            switch content.document.blocks[block] {
            case let .hunk(file, hunk):
                content.painter.drawHunk(content.files[file].patch.hunks[hunk], in: rect)
            case let .lines(file, hunk, left, right):
                let lines = content.files[file].patch.hunks[hunk].lines
                content.painter.drawLines(
                    left: left.map { lines[$0] },
                    right: right.map { lines[$0] },
                    in: rect,
                    columns: DiffRowPainter.Columns(sides: layout.sides(forFile: file), numberColumns: layout.numberColumns),
                    state: DiffRowPainter.RowState(
                        wrapped: { side, line in self.wrapped(block: block, side: side, line: line, content: content) },
                        selection: { [selection] side, length in
                            let isInline = content.document.style(ofBlock: block) == .inline
                            guard let selection, selection.side == side || isInline else { return nil }
                            return selection.range(inBlock: block, length: length)
                        },
                        isFocused: isFocused
                    )
                )
            case .header, .notice, .images:
                break
            }
        }
    }

    private func wrapped(block: Int, side: Int, line: DiffLine, content: Content) -> DiffRowPainter.Wrapped {
        let sides = content.layout.sides(forFile: content.document.blocks[block].file)
        let side = min(side, sides.count - 1)
        let columns = sides[side].textColumns
        guard line.columns > columns else {
            return DiffRowPainter.Wrapped(units: Array(line.text.utf16), lines: LineWrap.Lines(breaks: [], indent: 0))
        }
        let key = WrapKey(block: block, side: side)
        if let cached = wrapCache[key] {
            return cached
        }
        let units = Array(line.text.utf16)
        let wrapped = DiffRowPainter.Wrapped(units: units, lines: LineWrap.wrap(units, columns: columns))
        wrapCache[key] = wrapped
        return wrapped
    }

    override func mouseDown(with event: NSEvent) {
        guard let content, let window else { return }
        window.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        let side = side(at: location, layout: content.layout)
        let point = point(at: location, side: side, content: content)
        if event.modifierFlags.contains(.shift), var selection, selection.side == side {
            selection.head = point
            setSelection(selection)
        } else if event.clickCount == 2 {
            setSelection(word(at: point, side: side, content: content))
        } else if event.clickCount >= 3 {
            let length = DiffSelection.line(atBlock: point.block, side: side, document: content.document, files: content.files)?
                .text.utf16.count ?? 0
            setSelection(DiffSelection(
                side: side,
                anchor: DiffSelection.Point(block: point.block, offset: 0),
                head: DiffSelection.Point(block: point.block, offset: length)
            ))
        } else {
            setSelection(DiffSelection(side: side, anchor: point, head: point))
        }
        trackDrag(side: side)
    }

    /// Follows the pointer until the button comes up, scrolling when it leaves the view.
    private func trackDrag(side: Int) {
        guard let window else { return }
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp {
                break
            }
            autoscroll(with: event)
            guard let content, var selection else { continue }
            selection.head = point(at: convert(event.locationInWindow, from: nil), side: side, content: content)
            setSelection(selection)
        }
    }

    private func setSelection(_ selection: DiffSelection?) {
        guard selection != self.selection else { return }
        self.selection = selection
        needsDisplay = true
        onSelectionChange?()
    }

    private func side(at location: NSPoint, layout: DiffLayout) -> Int {
        layout.sides.count > 1 && location.x >= layout.sides[1].minX ? 1 : 0
    }

    /// The place in the text under a point. Past the text, it's the end of the visual line; left of
    /// it, the start.
    private func point(at location: NSPoint, side: Int, content: Content) -> DiffSelection.Point {
        let layout = content.layout
        guard layout.height > 0 else { return DiffSelection.Point(block: 0, offset: 0) }
        if location.y < 0 {
            return DiffSelection.Point(block: 0, offset: 0)
        }
        guard let block = layout.block(atY: location.y) else {
            let last = content.document.blocks.count - 1
            let length = DiffSelection.line(atBlock: last, side: side, document: content.document, files: content.files)?.text.utf16.count
            return DiffSelection.Point(block: last, offset: length ?? 0)
        }
        guard let line = DiffSelection.line(atBlock: block, side: side, document: content.document, files: content.files) else {
            return DiffSelection.Point(block: block, offset: 0)
        }
        let text = wrapped(block: block, side: side, line: line, content: content)
        let ranges = text.lines.ranges(length: text.units.count)
        let visualLine = min(max(Int((location.y - layout.top(of: block)) / layout.metrics.lineHeight), 0), ranges.count - 1)
        let range = ranges[visualLine]
        let sides = layout.sides(forFile: content.document.blocks[block].file)
        let textSide = sides[min(side, sides.count - 1)]
        let x = textSide.textX + Double(text.lines.textColumn(ofLine: visualLine)) * layout.metrics.advance
        guard location.x > x else { return DiffSelection.Point(block: block, offset: range.lowerBound) }
        let segment = content.painter.typesetText(String(decoding: text.units[range], as: UTF16.self))
        let index = CTLineGetStringIndexForPosition(segment, CGPoint(x: location.x - x, y: 0))
        let offset = index == kCFNotFound ? range.upperBound : range.lowerBound + min(max(index, 0), range.count)
        return DiffSelection.Point(block: block, offset: offset)
    }

    private func word(at point: DiffSelection.Point, side: Int, content: Content) -> DiffSelection {
        let units = DiffSelection.line(atBlock: point.block, side: side, document: content.document, files: content.files)
            .map { Array($0.text.utf16) } ?? []
        let token = ChangedWords.tokens(units).first { $0.contains(point.offset) || $0.upperBound == point.offset }
        return DiffSelection(
            side: side,
            anchor: DiffSelection.Point(block: point.block, offset: token?.lowerBound ?? point.offset),
            head: DiffSelection.Point(block: point.block, offset: token?.upperBound ?? point.offset)
        )
    }

    /// Everything on one side: the side last clicked, or the new version side by side.
    override func selectAll(_: Any?) {
        guard let content, !content.document.blocks.isEmpty else { return }
        let side = selection?.side ?? (content.layout.sides.count - 1)
        let last = content.document.blocks.count - 1
        let length = DiffSelection.line(atBlock: last, side: side, document: content.document, files: content.files)?.text.utf16.count ?? 0
        setSelection(DiffSelection(
            side: side,
            anchor: DiffSelection.Point(block: 0, offset: 0),
            head: DiffSelection.Point(block: last, offset: length)
        ))
    }

    @objc func copy(_: Any?) {
        guard let content, let selection, !selection.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection.text(document: content.document, files: content.files), forType: .string)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let content else { return nil }
        let location = convert(event.locationInWindow, from: nil)
        return makeMenu?(content.layout.block(atY: location.y).flatMap(content.document.file(at:)))
    }
}

/// Scrolling from the keyboard, since there's no text to move a cursor through.
extension DiffCanvasView {
    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    /// Space pages down and Shift-Space up, as in a browser, since there's no text to type into.
    override func insertText(_ insertString: Any) {
        guard (insertString as? String) == " " else {
            if let text = insertString as? String, onTypedKey?(text) == true {
                return
            }
            super.insertText(insertString)
            return
        }
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            scrollPageUp(nil)
        } else {
            scrollPageDown(nil)
        }
    }

    override func moveUp(_: Any?) {
        scroll(by: -(content?.layout.metrics.lineHeight ?? 16) * 3)
    }

    override func moveDown(_: Any?) {
        scroll(by: (content?.layout.metrics.lineHeight ?? 16) * 3)
    }

    override func scrollPageUp(_: Any?) {
        scroll(by: -pageHeight)
    }

    override func scrollPageDown(_: Any?) {
        scroll(by: pageHeight)
    }

    override func pageUp(_ sender: Any?) {
        scrollPageUp(sender)
    }

    override func pageDown(_ sender: Any?) {
        scrollPageDown(sender)
    }

    override func scrollToBeginningOfDocument(_: Any?) {
        scroll(to: 0)
    }

    override func scrollToEndOfDocument(_: Any?) {
        scroll(to: bounds.height)
    }

    override func moveToBeginningOfDocument(_ sender: Any?) {
        scrollToBeginningOfDocument(sender)
    }

    override func moveToEndOfDocument(_ sender: Any?) {
        scrollToEndOfDocument(sender)
    }

    /// Nothing to do for keys that don't scroll, rather than beeping at each one.
    override func doCommand(by selector: Selector) {
        if responds(to: selector) {
            perform(selector, with: nil)
        }
    }

    private var pageHeight: Double {
        max(visibleRect.height - (content?.layout.metrics.lineHeight ?? 16) * 2, 1)
    }

    private func scroll(by distance: Double) {
        scroll(to: visibleRect.minY + distance)
    }

    func scroll(to y: Double) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let maxY = max(bounds.height - clipView.bounds.height, 0)
        clipView.scroll(to: NSPoint(x: 0, y: min(max(y, 0), maxY)))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }
}

extension DiffCanvasView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)): selection.map { !$0.isEmpty } ?? false
        case #selector(selectAll(_:)): content != nil
        default: true
        }
    }
}
