import AppKit

/// Above a diff's files: how many there are and how many lines they add and remove, and a button
/// that collapses them all, or expands them all once they're all collapsed.
final class DiffSummaryBar: NSView {
    static let height = 30.0

    var onCollapseAll: (() -> Void)?
    var onExpandAll: (() -> Void)?

    private let summary = NSTextField(labelWithString: "")
    private let counts = NSTextField(labelWithString: "")
    private let button = NSButton(title: AppCommand.collapseAllFiles.title, target: nil, action: nil)
    private var isAllCollapsed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summary.textColor = .secondaryLabelColor
        counts.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        button.controlSize = .small
        button.bezelStyle = .push
        button.target = self
        button.action = #selector(toggleAll(_:))
        let stack = NSStackView()
        stack.setViews([summary, counts], in: .leading)
        stack.setViews([button], in: .trailing)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func show(files: [DiffFile], isAllCollapsed: Bool) {
        self.isAllCollapsed = isAllCollapsed
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
        button.title = isAllCollapsed ? AppCommand.expandAllFiles.title : AppCommand.collapseAllFiles.title
    }

    override func draw(_: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    @objc private func toggleAll(_: Any?) {
        if isAllCollapsed {
            onExpandAll?()
        } else {
            onCollapseAll?()
        }
    }
}
