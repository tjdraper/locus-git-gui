import AppKit

/// Buttons on a hunk's band, such as Stage Hunk, laid over the band the diff draws. The rest of the
/// band stays see-through, so what Git found the hunk to be inside still shows under it.
final class DiffHunkBarView: NSView {
    private let buttons = NSStackView()
    private var actions: [DiffAction] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        buttons.orientation = .horizontal
        buttons.spacing = 4
        buttons.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    func show(_ actions: [DiffAction]) {
        self.actions = actions
        let views = buttons.arrangedSubviews
        for (index, action) in actions.enumerated() {
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
        for view in views.dropFirst(actions.count) {
            view.removeFromSuperview()
        }
    }

    /// Only the buttons take clicks. Elsewhere the band is the diff's, as if the bar weren't there.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self || view === buttons ? nil : view
    }

    private func makeButton() -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(runAction(_:)))
        button.controlSize = .mini
        button.bezelStyle = .push
        button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .mini))
        return button
    }

    @objc private func runAction(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag].perform()
    }
}
