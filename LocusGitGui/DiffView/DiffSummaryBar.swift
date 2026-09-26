import AppKit

/// Above a diff's files: a disclosure triangle that collapses them all, or expands them all once
/// they're all collapsed, then how many there are and how many lines they add and remove. The
/// triangle lines up with the ones in the file headers below it. Whoever shows the diff can put a
/// control of its own on a row above, as the working area puts its filter.
final class DiffSummaryBar: NSView {
    private static let accessoryRowHeight = 30.0
    private static let filesRowHeight = 26.0

    var onCollapseAll: (() -> Void)?
    var onExpandAll: (() -> Void)?

    private let disclosure = NSButton()
    private let toggleTitle = NSButton(title: AppCommand.collapseAllFiles.title, target: nil, action: nil)
    private let summary = NSTextField(labelWithString: "")
    private let counts = NSTextField(labelWithString: "")
    private let accessoryRow = NSStackView()
    private let filesRow = NSStackView()
    private lazy var accessoryRowHeight = accessoryRow.heightAnchor.constraint(equalToConstant: 0)
    private var isAllCollapsed = false
    private var hasFiles = false

    var accessory: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let accessory {
                accessoryRow.setViews([accessory], in: .leading)
            }
            accessoryRow.isHidden = accessory == nil
            accessoryRowHeight.constant = accessory == nil ? 0 : Self.accessoryRowHeight
        }
    }

    /// Nothing is left to collapse without files, so only the accessory's row stays.
    var height: CGFloat {
        (accessory == nil ? 0 : Self.accessoryRowHeight) + (hasFiles ? Self.filesRowHeight : 0)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.pushOnPushOff)
        disclosure.title = ""
        toggleTitle.isBordered = false
        toggleTitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for button in [disclosure, toggleTitle] {
            button.target = self
            button.action = #selector(toggleAll(_:))
        }
        summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summary.textColor = .secondaryLabelColor
        counts.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        accessoryRow.orientation = .horizontal
        accessoryRow.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        accessoryRow.isHidden = true
        filesRow.setViews([disclosure, toggleTitle], in: .leading)
        filesRow.setViews([summary, counts], in: .trailing)
        filesRow.orientation = .horizontal
        filesRow.spacing = 6
        filesRow.setCustomSpacing(2, after: disclosure)
        // As the file headers' own, so the triangles line up.
        filesRow.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 12)
        for row in [accessoryRow, filesRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: leadingAnchor),
                row.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            accessoryRow.topAnchor.constraint(equalTo: topAnchor),
            accessoryRowHeight,
            filesRow.topAnchor.constraint(equalTo: accessoryRow.bottomAnchor),
            filesRow.heightAnchor.constraint(equalToConstant: Self.filesRowHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    func show(files: [DiffFile], isAllCollapsed: Bool) {
        self.isAllCollapsed = isAllCollapsed
        hasFiles = !files.isEmpty
        filesRow.isHidden = files.isEmpty
        summary.stringValue = files.count == 1 ? "1 file changed" : "\(files.count.formatted()) files changed"
        let removed = files.reduce(0) { $0 + $1.patch.removed }
        let added = files.reduce(0) { $0 + $1.patch.added }
        let text = NSMutableAttributedString()
        if removed > 0 {
            text.append(NSAttributedString(string: "−\(removed.formatted())", attributes: [.foregroundColor: NSColor.systemRed]))
        }
        if added > 0 {
            if text.length > 0 {
                text.append(NSAttributedString(string: " "))
            }
            text.append(NSAttributedString(string: "+\(added.formatted())", attributes: [.foregroundColor: NSColor.systemGreen]))
        }
        counts.attributedStringValue = text
        let title = isAllCollapsed ? AppCommand.expandAllFiles.title : AppCommand.collapseAllFiles.title
        toggleTitle.title = title
        disclosure.state = isAllCollapsed ? .off : .on
        disclosure.setAccessibilityLabel(title)
    }

    override func draw(_: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    @objc private func toggleAll(_: Any?) {
        if isAllCollapsed {
            onExpandAll?()
        } else {
            onCollapseAll?()
        }
    }
}
