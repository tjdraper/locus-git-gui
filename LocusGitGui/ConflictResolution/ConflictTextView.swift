import AppKit

/// One version of a conflicted file, in the diff's fixed-width font. A marked range fills its lines
/// across the whole width, as the diff fills its rows; a background attribute would only cover the
/// text, and leave blank lines unmarked. A marked range with no lines draws a line where they'd be.
final class ConflictTextView: NSTextView {
    struct Highlight: Equatable {
        let range: NSRange
        let color: NSColor
    }

    var highlights: [Highlight] = [] {
        didSet {
            if highlights != oldValue {
                needsDisplay = true
            }
        }
    }

    static func make(isEditable: Bool) -> (scrollView: NSScrollView, textView: ConflictTextView) {
        // Given a size to start from, since the text view follows the scroll view's changes in size
        // rather than taking its size, and a text view that starts with none keeps none.
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        let contentSize = scrollView.contentSize
        let textView = ConflictTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.useDiffFont()
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = isEditable
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // The text is code, which substitutions would change behind the user's back.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        scrollView.documentView = textView
        Task { [weak textView] in
            for await _ in NotificationCenter.default.notifications(named: DiffPreferences.didChange) {
                guard let textView else { return }
                textView.useDiffFont()
            }
        }
        return (scrollView, textView)
    }

    private func useDiffFont() {
        let font = DiffPreferences().font
        guard font != self.font else { return }
        self.font = font
        typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
    }

    /// Only the marks in the laid-out part of the text are looked at, so a file with thousands of
    /// conflicts draws as quickly as one with a few.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard !highlights.isEmpty, let layout = textLayoutManager, let content = layout.textContentManager else { return }
        let documentStart = content.documentRange.location
        guard let viewport = layout.textViewportLayoutController.viewportRange else { return }
        let visible = NSRange(
            location: content.offset(from: documentStart, to: viewport.location),
            length: content.offset(from: viewport.location, to: viewport.endLocation)
        )
        let shown = highlights.filter { NSMaxRange($0.range) >= visible.location && $0.range.location <= NSMaxRange(visible) }
        for highlight in shown {
            guard let frame = lineFrame(of: highlight.range, in: layout, content: content), frame.intersects(rect) else { continue }
            highlight.color.setFill()
            frame.fill(using: .sourceOver)
        }
    }

    private func lineFrame(of range: NSRange, in layout: NSTextLayoutManager, content: NSTextContentManager) -> NSRect? {
        let documentStart = content.documentRange.location
        let isAtEnd = range.location >= (string as NSString).length
        let startOffset = isAtEnd ? max(range.location - 1, 0) : range.location
        guard let start = content.location(documentStart, offsetBy: startOffset) else { return nil }
        var top = CGFloat.greatestFiniteMagnitude
        var bottom = -CGFloat.greatestFiniteMagnitude
        layout.enumerateTextLayoutFragments(from: start, options: []) { fragment in
            let fragmentStart = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            if top != .greatestFiniteMagnitude, fragmentStart >= NSMaxRange(range) {
                return false
            }
            top = min(top, fragment.layoutFragmentFrame.minY)
            bottom = max(bottom, fragment.layoutFragmentFrame.maxY)
            return range.length > 0
        }
        guard top <= bottom else { return nil }
        let origin = textContainerOrigin
        if range.length == 0 {
            let y = (isAtEnd ? bottom : top) + origin.y
            return NSRect(x: 0, y: y - 1, width: bounds.width, height: 2)
        }
        return NSRect(x: 0, y: top + origin.y, width: bounds.width, height: bottom - top)
    }

    /// Puts `range` in the middle of the view, rather than at its edge where `scrollRangeToVisible`
    /// leaves it.
    func scrollToMiddle(_ range: NSRange) {
        let length = (string as NSString).length
        let clamped = NSRange(location: min(range.location, length), length: 0)
        scrollRangeToVisible(clamped)
        guard let layout = textLayoutManager, let content = layout.textContentManager,
              let clipView = enclosingScrollView?.contentView,
              let frame = lineFrame(of: NSRange(location: clamped.location, length: max(range.length, 1)), in: layout, content: content)
        else { return }
        let visibleHeight = clipView.bounds.height
        let y = max(0, min(frame.midY - visibleHeight / 2, bounds.height - visibleHeight))
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: y))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }
}
