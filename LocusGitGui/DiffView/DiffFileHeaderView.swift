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
        /// The file the keyboard acts on, such as with Space in the working area.
        var isCurrent = false
        /// One of several files picked to act on together.
        var isSelected = false
    }

    var onToggle: (() -> Void)?
    /// Option-click, which collapses or expands every file.
    var onToggleAll: (() -> Void)?
    /// ⌘-click and Shift-click, which add the file to the files picked or take in the range up to it,
    /// as in Finder. Nil in a diff whose files aren't picked.
    var onCommandClick: (() -> Void)?
    var onShiftClick: (() -> Void)?
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
    private let actionButtons = NSStackView()
    private var actions: [DiffAction] = []
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
        path.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
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
        actionButtons.orientation = .horizontal
        actionButtons.spacing = 4
        // Otherwise it ties with the path for the room between the two ends, and lands at either.
        actionButtons.setHuggingPriority(.defaultHigh, for: .horizontal)
        let stack = NSStackView()
        stack.setViews([disclosure, changeSymbol, change, path, counts], in: .leading)
        stack.setViews([actionButtons, editorButton, moreButton], in: .trailing)
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
        if content.isCurrent != self.content?.isCurrent || content.isSelected != self.content?.isSelected {
            needsDisplay = true
        }
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

    /// Buttons for what whoever shows the diff can do to the file, such as staging it.
    func show(actions: [DiffAction]) {
        let actions = actions.filter { !$0.isInMenuOnly }
        self.actions = actions
        let views = actionButtons.arrangedSubviews
        for (index, action) in actions.enumerated() {
            let isCheckbox = action.isOn != nil
            var button = views.indices.contains(index) ? views[index] as? NSButton : nil
            if let existing = button, (existing.identifier == Self.checkboxIdentifier) != isCheckbox {
                existing.removeFromSuperview()
                button = nil
            }
            let shown = button ?? makeButton(isCheckbox: isCheckbox, at: index)
            shown.title = action.title
            shown.isEnabled = action.isEnabled
            shown.toolTip = action.toolTip
            shown.state = action.isOn == true ? .on : .off
            shown.tag = index
        }
        for view in actionButtons.arrangedSubviews.dropFirst(actions.count) {
            view.removeFromSuperview()
        }
    }

    private static let checkboxIdentifier = NSUserInterfaceItemIdentifier("DiffActionCheckbox")

    private func makeButton(isCheckbox: Bool, at index: Int) -> NSButton {
        let button = if isCheckbox {
            NSButton(checkboxWithTitle: "", target: self, action: #selector(runAction(_:)))
        } else {
            NSButton(title: "", target: self, action: #selector(runAction(_:)))
        }
        button.controlSize = .small
        if isCheckbox {
            button.identifier = Self.checkboxIdentifier
        } else {
            button.bezelStyle = .push
        }
        actionButtons.insertArrangedSubview(button, at: min(index, actionButtons.arrangedSubviews.count))
        return button
    }

    @objc private func runAction(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag].perform()
    }

    /// Opaque, since the diff scrolls under it while it's stuck at the top. A stronger fill than the
    /// hunk bands below it, and a line at the top as well as the bottom, so it reads as the start of
    /// a file rather than another band.
    override func draw(_: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.tertiarySystemFill.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        if content?.isSelected == true {
            NSColor.controlAccentColor.withAlphaComponent(0.24).setFill()
            bounds.fill()
        }
        // Only a bar for the current file, since something is always current while the diff has
        // focus, and a fill there read as a picked file.
        if content?.isCurrent == true {
            NSColor.controlAccentColor.setFill()
            NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
        }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    /// Every click, so a double-click collapses the file and expands it again.
    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, let onCommandClick {
            onCommandClick()
        } else if modifiers == .shift, let onShiftClick {
            onShiftClick()
        } else {
            toggle(allFiles: modifiers.contains(.option))
        }
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
