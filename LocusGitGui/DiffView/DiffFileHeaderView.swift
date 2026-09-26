import AppKit

/// The bar above each file in a diff: its path, how many lines it adds and removes, and what can be
/// done with it. Clicking it collapses or expands the file. The one for the file at the top stays in
/// view while the file scrolls under it.
final class DiffFileHeaderView: NSView {
    struct Content: Equatable {
        let file: ChangedFile
        let added: Int
        let removed: Int
        let isCollapsed: Bool
        let isInWorkingTree: Bool
    }

    var onToggle: (() -> Void)?
    /// Option-click, which collapses or expands every file.
    var onToggleAll: (() -> Void)?
    var onOpenInEditor: (() -> Void)?
    /// Built when the "…" button is pressed, so it names the file as it is then.
    var makeMenu: (() -> NSMenu)?

    private let disclosure = NSButton()
    private let change = NSTextField(labelWithString: "")
    /// Added and deleted files have a symbol in place of the word, so they stand out in a long list.
    private let changeSymbol = NSImageView()
    private let path = NSTextField(labelWithString: "")
    private let counts = NSTextField(labelWithString: "")
    private let editorButton = NSButton()
    private let moreButton = NSButton()
    private var content: Content?

    override init(frame: NSRect) {
        super.init(frame: frame)
        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.pushOnPushOff)
        disclosure.title = ""
        disclosure.target = self
        disclosure.action = #selector(toggle(_:))
        change.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        change.textColor = .secondaryLabelColor
        path.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        path.lineBreakMode = .byTruncatingHead
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        counts.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        for (button, symbol, label) in [
            (editorButton, "square.and.pencil", AppCommand.openInEditor.title),
            (moreButton, "ellipsis.circle", "More"),
        ] {
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.toolTip = label
            button.target = self
        }
        editorButton.action = #selector(openInEditor(_:))
        moreButton.action = #selector(showMenu(_:))
        let stack = NSStackView()
        stack.setViews([disclosure, changeSymbol, change, path, counts], in: .leading)
        stack.setViews([editorButton, moreButton], in: .trailing)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.setCustomSpacing(10, after: path)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        guard content != self.content else { return }
        self.content = content
        let file = content.file
        disclosure.state = content.isCollapsed ? .off : .on
        let symbol: (name: String, color: NSColor)? = switch file.change {
        case .added: ("plus.circle.fill", .systemGreen)
        case .deleted: ("trash.fill", .systemRed)
        default: nil
        }
        changeSymbol.image = symbol.flatMap { NSImage(systemSymbolName: $0.name, accessibilityDescription: file.change.title) }
        changeSymbol.contentTintColor = symbol?.color
        changeSymbol.toolTip = symbol == nil ? nil : file.change.title
        changeSymbol.isHidden = symbol == nil
        change.stringValue = file.change.title
        change.isHidden = file.change == .modified || symbol != nil
        path.stringValue = file.originalPath.map { "\($0) → \(file.path)" } ?? file.path
        path.toolTip = path.stringValue
        let counts = NSMutableAttributedString()
        if content.removed > 0 {
            counts.append(NSAttributedString(string: "−\(content.removed.formatted())", attributes: [.foregroundColor: NSColor.systemRed]))
        }
        if content.added > 0 {
            if counts.length > 0 {
                counts.append(NSAttributedString(string: " "))
            }
            counts.append(NSAttributedString(string: "+\(content.added.formatted())", attributes: [.foregroundColor: NSColor.systemGreen]))
        }
        self.counts.attributedStringValue = counts
        editorButton.isEnabled = content.isInWorkingTree
        setAccessibilityLabel(path.stringValue)
        disclosure.setAccessibilityLabel(path.stringValue)
    }

    /// Opaque, since the diff scrolls under it while it's stuck at the top.
    override func draw(_: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.quaternarySystemFill.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    /// Every click, so a double-click collapses the file and expands it again.
    override func mouseDown(with event: NSEvent) {
        toggle(allFiles: event.modifierFlags.contains(.option))
    }

    private func toggle(allFiles: Bool) {
        if allFiles {
            onToggleAll?()
        } else {
            onToggle?()
        }
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        makeMenu?()
    }

    @objc private func toggle(_: Any?) {
        toggle(allFiles: NSApp.currentEvent?.modifierFlags.contains(.option) == true)
    }

    @objc private func openInEditor(_: Any?) {
        onOpenInEditor?()
    }

    @objc private func showMenu(_ sender: NSButton) {
        guard let menu = makeMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }
}
