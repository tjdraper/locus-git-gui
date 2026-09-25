import AppKit
import SwiftUI

/// The dashboard: every repository opened before, searchable and driven from the keyboard. It's
/// transient, and closes as soon as a repository opens.
final class DashboardWindowPresenter: NSObject, NSWindowDelegate, NSMenuItemValidation {
    private static let removeActionName = "Remove from List"

    /// Its commands act on the dashboard's selection, so they show in the File menu only while it's
    /// in front.
    let fileMenuItems: [NSMenuItem]
    let viewMenuItems: [NSMenuItem]

    private let session: DashboardSession
    private let recents: RecentRepositoryStore
    private let checker: RecentRepositoryChecker
    private let opener: RecentRepositoryOpener
    private let displayNames: DisplayNameWorkflow
    private let showOpenPanel: () -> Void
    private var window: DashboardWindow?
    /// The window in front when File > New Tab opened the dashboard.
    private weak var tabHost: NSWindow?

    init(
        recents: RecentRepositoryStore,
        checker: RecentRepositoryChecker,
        opener: RecentRepositoryOpener,
        displayNames: DisplayNameWorkflow,
        showOpenPanel: @escaping () -> Void
    ) {
        session = DashboardSession(recents: recents)
        self.recents = recents
        self.checker = checker
        self.opener = opener
        self.displayNames = displayNames
        self.showOpenPanel = showOpenPanel
        fileMenuItems = [
            .separator(),
            Self.menuItem(DashboardCommandTitle.open(1), #selector(openSelection(_:)), "\r", []),
            Self.menuItem(DashboardCommandTitle.remove(1), #selector(removeSelection(_:)), "\u{8}", .command),
            Self.menuItem(DashboardCommandTitle.removeAllMissing, #selector(removeAllMissing(_:)), "\u{8}", [.command, .option]),
            Self.menuItem(DashboardCommandTitle.showInFinder, #selector(showSelectionInFinder(_:)), "\r", .command),
            Self.menuItem(DashboardCommandTitle.setDisplayName, #selector(setDisplayNameOfSelection(_:)), "", []),
        ]
        viewMenuItems = [
            .separator(),
            Self.menuItem(DashboardCommandTitle.showOnlyMissing, #selector(toggleShowOnlyMissing(_:)), "m", [.command, .shift]),
        ]
        super.init()
        for item in fileMenuItems + viewMenuItems {
            item.target = self
            item.isHidden = true
        }
        checker.onScanned = { [session] findings in session.record(findings) }
        checker.onChecked = { [session] repository, state in session.record(state, for: repository) }
    }

    func show() {
        tabHost = nil
        present()
    }

    /// What opens from the dashboard joins the tabs of `window`. Asked again with no window, such
    /// as while the dashboard itself is in front, it keeps the one it had.
    func showForNewTab(joining window: NSWindow?) {
        if let window {
            tabHost = window
        }
        present()
    }

    private func present() {
        let window = window ?? makeWindow()
        self.window = window
        session.opened(clearingSearch: !window.isVisible)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    /// Also covers a repository moved, deleted or switched to another branch while the dashboard
    /// was behind something else.
    func windowDidBecomeKey(_: Notification) {
        setMenuItemsHidden(false)
        checker.startRound(with: recents.entries.map(\.repository))
    }

    func windowDidEndSheet(_: Notification) {
        session.focusSearch()
    }

    func windowDidResignKey(_: Notification) {
        setMenuItemsHidden(true)
    }

    /// What Undo would bring back can't be seen once the window is gone.
    func windowWillClose(_: Notification) {
        tabHost = nil
        checker.stop()
        window?.undoManager?.removeAllActions()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let selected = session.selectedRows
        switch menuItem.action {
        case #selector(openSelection(_:)):
            menuItem.title = DashboardCommandTitle.open(selected.count)
            // While an input method is composing text, Return commits it.
            return !selected.isEmpty && (window?.firstResponder as? NSTextView)?.hasMarkedText() != true
        case #selector(removeSelection(_:)):
            menuItem.title = DashboardCommandTitle.remove(selected.count)
            return !selected.isEmpty
        case #selector(removeAllMissing(_:)):
            return !session.missingRepositories.isEmpty
        case #selector(showSelectionInFinder(_:)):
            return selected.count == 1 && selected.allSatisfy(session.canShowInFinder)
        case #selector(setDisplayNameOfSelection(_:)):
            return selected.count == 1 && selected.allSatisfy(session.canSetDisplayName)
        case #selector(toggleShowOnlyMissing(_:)):
            menuItem.state = session.showsOnlyMissing ? .on : .off
            return !session.missingRepositories.isEmpty
        default:
            return true
        }
    }

    @objc private func openSelection(_: Any?) {
        open(session.selectedRows)
    }

    @objc private func removeSelection(_: Any?) {
        remove(session.selectedRows.map(\.repository))
    }

    @objc private func removeAllMissing(_: Any?) {
        remove(session.missingRepositories)
    }

    @objc private func showSelectionInFinder(_: Any?) {
        if let row = session.selectedRows.first {
            showInFinder(row)
        }
    }

    @objc private func setDisplayNameOfSelection(_: Any?) {
        if let row = session.selectedRows.first {
            setDisplayName(of: row)
        }
    }

    @objc private func toggleShowOnlyMissing(_: Any?) {
        session.showsOnlyMissing.toggle()
    }

    private func makeWindow() -> DashboardWindow {
        let window = DashboardWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Locus Git Gui Dashboard"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: DashboardView(
            session: session,
            actions: DashboardView.Actions(
                open: { [weak self] rows in self?.open(rows) },
                remove: { [weak self] rows in self?.remove(rows.map(\.repository)) },
                removeAllMissing: { [weak self] in self?.removeAllMissing(nil) },
                setDisplayName: { [weak self] row in self?.setDisplayName(of: row) },
                showInFinder: { [weak self] row in self?.showInFinder(row) },
                showOpenPanel: showOpenPanel,
                rowAppeared: { [checker] row in checker.rowAppeared(row.repository) },
                rowDisappeared: { [checker] row in checker.rowDisappeared(row.repository) }
            )
        ))
        window.onKeyCommand = { [weak self] command in self?.perform(command) }
        RememberedWindowPlacement(autosaveName: "Dashboard").apply(to: window, initialContentSize: NSSize(width: 600, height: 480))
        return window
    }

    private func perform(_ command: DashboardWindow.KeyCommand) {
        switch command {
        case let .moveUp(extending):
            session.moveSelection(by: -1, extending: extending)
        case let .moveDown(extending):
            session.moveSelection(by: 1, extending: extending)
        case .open:
            open(session.selectedRows)
        case .close:
            close()
        }
    }

    private func open(_ rows: [DashboardRow]) {
        guard !rows.isEmpty else { return }
        session.noteOpened(rows)
        let knownMissing = Set(rows.filter { session.state(of: $0.id) == .missing }.map(\.id))
        opener.open(rows.map(\.repository), knownMissing: knownMissing, over: window, inTabsOf: tabHost)
    }

    private func showInFinder(_ row: DashboardRow) {
        NSWorkspace.shared.activateFileViewerSelecting([row.repository.workTree])
    }

    private func setDisplayName(of row: DashboardRow) {
        guard let window else { return }
        displayNames.edit(row.repository, over: window)
    }

    /// Undoing puts them back where they were, and redoing removes them again.
    private func remove(_ repositories: [Repository]) {
        guard !repositories.isEmpty else { return }
        let removed = session.remove(repositories)
        window?.undoManager?.registerUndo(withTarget: self) { presenter in
            presenter.restore(removed)
        }
        window?.undoManager?.setActionName(Self.removeActionName)
    }

    private func restore(_ removed: [RecentRepositoryList.Removal]) {
        session.restore(removed)
        window?.undoManager?.registerUndo(withTarget: self) { presenter in
            presenter.remove(removed.map(\.entry.repository))
        }
        window?.undoManager?.setActionName(Self.removeActionName)
    }

    private func setMenuItemsHidden(_ isHidden: Bool) {
        for item in fileMenuItems + viewMenuItems {
            item.isHidden = isHidden
        }
    }

    private static func menuItem(
        _ title: String,
        _ action: Selector,
        _ keyEquivalent: String,
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
