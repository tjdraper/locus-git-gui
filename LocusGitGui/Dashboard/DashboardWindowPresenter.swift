import AppKit
import SwiftUI

/// The dashboard: every repository opened before, searchable and driven from the keyboard. It's
/// transient, and closes as soon as a repository opens.
final class DashboardWindowPresenter: NSObject, NSWindowDelegate {
    private let session: DashboardSession
    private let recents: RecentRepositoryStore
    private let checker: RecentRepositoryChecker
    private let opener: RecentRepositoryOpener
    private let showOpenPanel: () -> Void
    private var window: DashboardWindow?
    private var checking: Task<Void, Never>?

    init(
        recents: RecentRepositoryStore,
        checker: RecentRepositoryChecker,
        opener: RecentRepositoryOpener,
        showOpenPanel: @escaping () -> Void
    ) {
        session = DashboardSession(recents: recents)
        self.recents = recents
        self.checker = checker
        self.opener = opener
        self.showOpenPanel = showOpenPanel
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        session.opened(clearingSearch: !window.isVisible)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    /// Also covers a repository moved or deleted in Finder while the dashboard was open.
    func windowDidBecomeKey(_: Notification) {
        checkRecentRepositories()
    }

    func windowWillClose(_: Notification) {
        checking?.cancel()
        checking = nil
    }

    private func makeWindow() -> DashboardWindow {
        let window = DashboardWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dashboard"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: DashboardView(
            session: session,
            onOpen: { [weak self] row in self?.open(row) },
            onRemove: { [weak self] row in self?.session.remove(row) },
            onShowOpenPanel: showOpenPanel
        ))
        window.setContentSize(NSSize(width: 600, height: 480))
        window.onKeyCommand = { [weak self] command in self?.perform(command) }
        window.center()
        return window
    }

    private func perform(_ command: DashboardWindow.KeyCommand) {
        switch command {
        case .moveUp:
            session.moveSelection(by: -1)
        case .moveDown:
            session.moveSelection(by: 1)
        case .open:
            if let row = session.selectedRow {
                open(row)
            }
        case .close:
            close()
        case .removeFromList:
            if let row = session.selectedRow {
                session.remove(row)
            }
        }
    }

    private func open(_ row: DashboardRow) {
        opener.open(row.repository, isMissing: session.states[row.id] == .missing, over: window)
    }

    /// A check already underway finishes rather than starting over, since the window becomes key
    /// every time the user comes back to it.
    private func checkRecentRepositories() {
        guard checking == nil else { return }
        let repositories = recents.repositories
        checking = Task { [weak self, checker, session] in
            await checker.check(repositories) { repository, state in
                session.record(state, for: repository)
            }
            // Closing the window already cleared it, and a later check may have taken its place.
            if !Task.isCancelled {
                self?.checking = nil
            }
        }
    }
}
