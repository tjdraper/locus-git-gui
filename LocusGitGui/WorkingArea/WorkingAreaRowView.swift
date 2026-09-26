import AppKit

/// The history's first row, above every commit: the changes not yet committed, with how many files
/// are staged, unstaged and untracked. Its text starts where the commits' subjects do.
final class WorkingAreaRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("WorkingAreaRow")
    static let title = "Uncommitted Changes"

    private static let verticalPadding: CGFloat = 4
    private static let trailingPadding: CGFloat = 8
    private static let circleRadius: CGFloat = 4

    private let titleField = NSTextField(labelWithString: title)
    private let details = NSTextField(labelWithString: "")
    private var textStart: CGFloat = 0
    private var showsCircle = false

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        titleField.lineBreakMode = .byTruncatingTail
        titleField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        details.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        details.textColor = .secondaryLabelColor
        details.lineBreakMode = .byTruncatingTail
        textField = titleField
        addSubview(titleField)
        addSubview(details)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    /// `graphWidth` is the width of the commits' graph, which is zero during a search.
    func show(_ summary: WorkingAreaSummary, graphWidth: CGFloat, graphPadding: CGFloat) {
        details.stringValue = summary.description
        showsCircle = graphWidth > 0
        textStart = graphWidth + graphPadding
        setAccessibilityLabel("\(Self.title), \(summary.description)")
        details.cell?.backgroundStyle = backgroundStyle
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let width = max(bounds.width - textStart - Self.trailingPadding, 0)
        let titleHeight = titleField.intrinsicContentSize.height
        titleField.frame = NSRect(x: textStart, y: Self.verticalPadding, width: width, height: titleHeight)
        let detailsHeight = details.intrinsicContentSize.height
        details.frame = NSRect(x: textStart, y: bounds.height - Self.verticalPadding - detailsHeight, width: width, height: detailsHeight)
    }

    /// A hollow dot in the graph's first lane, where the next commit would go.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsCircle else { return }
        let center = NSPoint(x: CommitGraphView.laneWidth / 2, y: bounds.midY)
        let circle = NSBezierPath(ovalIn: NSRect(
            x: center.x - Self.circleRadius,
            y: center.y - Self.circleRadius,
            width: Self.circleRadius * 2,
            height: Self.circleRadius * 2
        ))
        circle.lineWidth = 1.5
        (backgroundStyle == .emphasized ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor).setStroke()
        circle.stroke()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            details.cell?.backgroundStyle = backgroundStyle
            needsDisplay = true
        }
    }
}
