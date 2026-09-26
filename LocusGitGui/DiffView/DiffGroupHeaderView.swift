import AppKit

/// The heading above a group of files in a grouped diff, such as the working area's staged changes,
/// with how many files it holds and what can be done to all of them.
final class DiffGroupHeaderView: NSView {
    struct Content {
        let title: String
        let fileCount: Int
        let actions: [DiffAction]
    }

    private let title = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let buttons = NSStackView()
    private var actions: [DiffAction] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .bold)
        count.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        count.textColor = .secondaryLabelColor
        buttons.orientation = .horizontal
        buttons.spacing = 6
        let stack = NSStackView()
        stack.setViews([title, count], in: .leading)
        stack.setViews([buttons], in: .trailing)
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    func show(_ content: Content) {
        title.stringValue = content.title
        count.stringValue = content.fileCount == 1 ? "1 file" : "\(content.fileCount.formatted()) files"
        setAccessibilityLabel("\(content.title), \(count.stringValue)")
        actions = content.actions
        let views = buttons.arrangedSubviews
        for (index, action) in content.actions.enumerated() {
            let button = views.indices.contains(index) ? views[index] as? NSButton : nil
            let shown = button ?? makeButton()
            if button == nil {
                buttons.addArrangedSubview(shown)
            }
            shown.title = action.title
            shown.isEnabled = action.isEnabled
            shown.toolTip = action.toolTip
            shown.tag = index
        }
        for view in views.dropFirst(content.actions.count) {
            view.removeFromSuperview()
        }
    }

    private func makeButton() -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(runAction(_:)))
        button.controlSize = .small
        button.bezelStyle = .push
        return button
    }

    override func draw(_: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
    }

    @objc private func runAction(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag].perform()
    }
}
