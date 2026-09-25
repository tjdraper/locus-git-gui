import AppKit

/// The command palette: every menu command that's enabled for the window in front, searchable from
/// the keyboard, and jumps to the branches, tags and stashes that window holds.
final class CommandPalettePresenter: NSObject, NSMenuItemValidation {
    private static let historyKey = "CommandPaletteHistory"
    /// Below the window's toolbar, so the palette doesn't cover its title.
    private static let gapBelowToolbar: CGFloat = 12

    let paletteMenuItems: [NSMenuItem]
    let goToMenuItems: [NSMenuItem]

    private let defaults: UserDefaults
    private var history: SearchPickHistory
    private let panel = CommandPalettePanel()
    /// Nil while the palette is closed.
    private var session: CommandPaletteSession?
    /// The window the palette was opened over, which its commands act on.
    private weak var sourceWindow: NSWindow?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        history = SearchPickHistory(defaults: defaults, key: Self.historyKey)
        paletteMenuItems = AppCommand.commandPalette.makeMenuItems()
        goToMenuItems = [AppCommand.goToBranch, .goToTag, .goToStash].map { $0.makeMenuItem() }
        super.init()
        for item in paletteMenuItems + goToMenuItems {
            item.target = self
        }
        panel.onKeyCommand = { [weak self] command in self?.perform(command) ?? false }
        // Focus has already gone to wherever the user clicked or switched to, so it stays there.
        panel.onResignKey = { [weak self] in self?.dismiss(restoringFocus: false) }
    }

    /// Opening it again while it's open goes back to the commands, or closes it when it's already
    /// showing them.
    @objc func showCommandPalette(_: Any?) {
        guard let session else {
            sourceWindow = NSApp.keyWindow
            open(with: commandStep())
            return
        }
        if session.isAtFirstStep {
            dismiss(restoringFocus: true)
        } else {
            session.returnToFirstStep()
        }
    }

    @objc func goToBranch(_: Any?) {
        goTo(.goToBranch)
    }

    @objc func goToTag(_: Any?) {
        goTo(.goToTag)
    }

    @objc func goToStash(_: Any?) {
        goTo(.goToStash)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard NSApp.modalWindow == nil else { return false }
        // A sheet or another panel is in front only for a moment, and its commands aren't the app's.
        if let window = windowInFront, window.isSheet || window.attachedSheet != nil || window is NSPanel {
            return false
        }
        guard let command = AppCommand(menuItem: menuItem), let kinds = Self.destinationKinds(for: command) else {
            return true
        }
        return destinations.contains { kinds.contains($0.kind) }
    }

    /// While the palette is open, the window it was opened over rather than the palette itself.
    private var windowInFront: NSWindow? {
        session == nil ? NSApp.keyWindow : sourceWindow
    }

    private var destinations: [CommandPaletteDestination] {
        (windowInFront?.windowController as? CommandPaletteDestinationSource)?.paletteDestinations ?? []
    }

    private func goTo(_ command: AppCommand) {
        if let session {
            session.push(destinationStep(for: command, among: destinations))
        } else {
            sourceWindow = NSApp.keyWindow
            open(with: destinationStep(for: command, among: destinations))
        }
    }

    private func open(with step: CommandPaletteStep) {
        let session = CommandPaletteSession(step: step, history: history)
        self.session = session
        panel.setRootView(CommandPaletteView(
            session: session,
            choose: { [weak self] index in self?.choose(at: index) },
            heightChanged: { [weak self] height in self?.panel.setContentHeight(height) }
        ))
        place()
        sourceWindow?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    /// The menu bar's commands, then everything in the window that can be jumped to, which waits
    /// for a search. Read while `sourceWindow` still has focus, since the menus validate against the
    /// window that has it.
    private func commandStep() -> CommandPaletteStep {
        let destinations = destinations
        let commands = MenuBarCommandReader.read(excluding: [.commandPalette]).map { entry in
            guard let command = AppCommand(rawValue: entry.item.id), Self.destinationKinds(for: command) != nil else {
                return entry
            }
            let step = destinationStep(for: command, among: destinations)
            return CommandPaletteEntry(item: entry.item, action: .ask { step })
        }
        return CommandPaletteStep(
            placeholder: destinations.isEmpty ? "Search Commands" : "Search Commands, Branches, Tags and Stashes",
            entries: commands + destinations.map { $0.entry(isListedBeforeTyping: false) }
        )
    }

    private func destinationStep(for command: AppCommand, among destinations: [CommandPaletteDestination]) -> CommandPaletteStep {
        let kinds = Self.destinationKinds(for: command) ?? []
        return CommandPaletteStep(
            placeholder: Self.destinationPlaceholder(for: command),
            entries: destinations.filter { kinds.contains($0.kind) }.map { $0.entry(isListedBeforeTyping: true) }
        )
    }

    private func choose(at index: Int) {
        session?.select(index)
        chooseSelection()
    }

    private func chooseSelection() {
        guard let session, let entry = session.selectedEntry else { return }
        history.record(term: FuzzyMatcher.fold(session.query), item: entry.item.id, at: .now)
        history.save(to: defaults, key: Self.historyKey)
        switch entry.action {
        case let .ask(makeStep):
            session.push(makeStep())
        case let .perform(action):
            dismiss(restoringFocus: true)
            action()
        }
    }

    private func perform(_ command: CommandPalettePanel.KeyCommand) -> Bool {
        guard let session else { return false }
        switch command {
        case .moveUp:
            session.moveSelection(by: -1)
        case .moveDown:
            session.moveSelection(by: 1)
        case .choose:
            chooseSelection()
        case .back:
            if !session.goBack() {
                dismiss(restoringFocus: true)
            }
        case .deleteBackward:
            guard session.query.isEmpty, session.goBack() else { return false }
        }
        return true
    }

    /// The command chosen acts on the window the palette was opened over, so that window has focus
    /// again before it runs.
    private func dismiss(restoringFocus: Bool) {
        guard session != nil else { return }
        session = nil
        let source = sourceWindow
        source?.removeChildWindow(panel)
        panel.orderOut(nil)
        if restoringFocus, let source, source.isVisible {
            source.makeKey()
        }
    }

    /// Centered near the top of the window it's over, like a sheet, or of the screen with no window.
    private func place() {
        let size = NSSize(width: CommandPaletteView.width, height: panel.frame.height)
        let top: CGFloat
        let midX: CGFloat
        if let window = sourceWindow {
            top = window.convertToScreen(window.contentLayoutRect).maxY - Self.gapBelowToolbar
            midX = window.frame.midX
        } else if let screen = NSScreen.main {
            top = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.2
            midX = screen.visibleFrame.midX
        } else {
            return
        }
        panel.setFrame(NSRect(x: midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: false)
    }

    private static func destinationKinds(for command: AppCommand) -> Set<CommandPaletteDestination.Kind>? {
        switch command {
        case .goToBranch: [.branch, .remoteBranch]
        case .goToTag: [.tag]
        case .goToStash: [.stash]
        default: nil
        }
    }

    private static func destinationPlaceholder(for command: AppCommand) -> String {
        switch command {
        case .goToTag: "Go to Tag"
        case .goToStash: "Go to Stash"
        default: "Go to Branch"
        }
    }
}
