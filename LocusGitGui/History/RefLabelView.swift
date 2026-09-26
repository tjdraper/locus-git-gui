import AppKit

/// A branch, remote branch or tag drawn as a small tinted capsule, with the symbol the sidebar
/// shows for it.
final class RefLabelView: NSView {
    private static let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    private static let checkedOutFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
    private static let padding = NSSize(width: 5, height: 1)
    private static let symbolGap: CGFloat = 3
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)

    /// Changed for the label counting the labels that didn't fit.
    var text: String {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private let kind: CommitRefLabel.Kind?

    var isEmphasized = false {
        didSet { needsDisplay = true }
    }

    /// Nil `kind` for the count of labels that didn't fit, which has no symbol.
    init(text: String, kind: CommitRefLabel.Kind?, description: String) {
        self.text = text
        self.kind = kind
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(description)
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

    /// The sidebar's symbol for each, and a pin for a detached HEAD, which the sidebar has no row
    /// for: where HEAD is, without a branch.
    static func symbolName(for kind: CommitRefLabel.Kind) -> String {
        switch kind {
        case .head: "mappin"
        case .checkedOutBranch: "checkmark.circle.fill"
        case .branch, .remoteBranch: "arrow.triangle.branch"
        case .tag: "tag"
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
        let symbolWidth = symbol(color: .labelColor).map { $0.size.width + Self.symbolGap } ?? 0
        return NSSize(
            width: ceil(size.width + symbolWidth) + Self.padding.width * 2,
            height: ceil(size.height) + Self.padding.height * 2
        )
    }

    override var isFlipped: Bool {
        true
    }

    private var font: NSFont {
        kind == .checkedOutBranch ? Self.checkedOutFont : Self.font
    }

    private func symbol(color: NSColor) -> NSImage? {
        guard let kind else { return nil }
        return NSImage(systemSymbolName: Self.symbolName(for: kind), accessibilityDescription: nil)?
            .withSymbolConfiguration(Self.symbolConfiguration.applying(.init(hierarchicalColor: color)))
    }

    override func draw(_: NSRect) {
        let background = isEmphasized
            ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.25)
            : Self.tint(for: kind).withAlphaComponent(kind == .checkedOutBranch ? 0.3 : 0.18)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let foreground = isEmphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor
        var x = Self.padding.width
        if let symbol = symbol(color: foreground) {
            let size = symbol.size
            symbol.draw(in: NSRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
            x += size.width + Self.symbolGap
        }
        (text as NSString).draw(
            at: NSPoint(x: x, y: Self.padding.height),
            withAttributes: [.font: font, .foregroundColor: foreground]
        )
    }
}
