import AppKit

/// A branch, remote branch or tag drawn as a small tinted capsule beside a commit's subject.
final class RefLabelView: NSView {
    private static let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    private static let checkedOutFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
    private static let padding = NSSize(width: 5, height: 1)

    private let text: String
    private let kind: CommitRefLabel.Kind?

    var isEmphasized = false {
        didSet { needsDisplay = true }
    }

    /// Nil `kind` for the count of labels that didn't fit.
    init(text: String, kind: CommitRefLabel.Kind?, description: String) {
        self.text = text
        self.kind = kind
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(description)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    convenience init(_ label: CommitRefLabel) {
        self.init(text: label.name, kind: label.kind, description: Self.describe(label))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    static func tint(for kind: CommitRefLabel.Kind?) -> NSColor {
        switch kind {
        case .checkedOutBranch, .branch: .systemBlue
        case .remoteBranch: .systemPurple
        case .tag: .systemOrange
        case .head, nil: .systemGray
        }
    }

    static func describe(_ label: CommitRefLabel) -> String {
        switch label.kind {
        case .head: "HEAD"
        case .checkedOutBranch: "Checked-out branch \(label.name)"
        case .branch: "Branch \(label.name)"
        case .remoteBranch: "Remote branch \(label.name)"
        case .tag: "Tag \(label.name)"
        }
    }

    override var intrinsicContentSize: NSSize {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(size.width) + Self.padding.width * 2, height: ceil(size.height) + Self.padding.height * 2)
    }

    private var font: NSFont {
        kind == .checkedOutBranch ? Self.checkedOutFont : Self.font
    }

    override func draw(_: NSRect) {
        let background = isEmphasized
            ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.25)
            : Self.tint(for: kind).withAlphaComponent(kind == .checkedOutBranch ? 0.3 : 0.18)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let foreground = isEmphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor
        (text as NSString).draw(
            at: NSPoint(x: Self.padding.width, y: Self.padding.height),
            withAttributes: [.font: font, .foregroundColor: foreground]
        )
    }
}
