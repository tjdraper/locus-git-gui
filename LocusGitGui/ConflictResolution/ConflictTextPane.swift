import AppKit

/// One of the conflict window's panes: a title naming the version, with the colour that marks its
/// lines, above the version's text.
final class ConflictTextPane: NSView {
    let textView: ConflictTextView
    private let titleField = NSTextField(labelWithString: "")
    private let swatch: Swatch
    private let detailField = NSTextField(labelWithString: "")

    init(color: NSColor?, isEditable: Bool) {
        let (scrollView, textView) = ConflictTextView.make(isEditable: isEditable)
        self.textView = textView
        swatch = Swatch(color: color)
        super.init(frame: .zero)
        titleField.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        detailField.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        swatch.isHidden = color == nil
        let header = NSStackView(views: [swatch, titleField, detailField])
        header.orientation = .horizontal
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        header.setHuggingPriority(.defaultLow, for: .horizontal)
        let separator = NSBox()
        separator.boxType = .separator
        for subview in [header, separator, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 8),
            swatch.heightAnchor.constraint(equalToConstant: 8),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            // So a divider dragged, or a size remembered, can't close a pane up entirely.
            heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func setTitle(_ title: String, detail: String = "") {
        titleField.stringValue = title
        titleField.toolTip = title
        detailField.stringValue = detail
    }

    func setText(_ text: String) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }
}

/// Drawn rather than given a layer colour, so it follows light and dark mode by itself.
private final class Swatch: NSView {
    private let color: NSColor?

    init(color: NSColor?) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_: NSRect) {
        color?.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }
}
