import AppKit
import SwiftUI

/// The Activity window for one repository, opened from View > Show Activity or the toolbar's
/// activity indicator.
final class ActivityWindowPresenter {
    private let log: GitCommandLog
    private let repository: Repository
    private var window: NSWindow?

    init(log: GitCommandLog, repository: Repository) {
        self.log = log
        self.repository = repository
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: ActivityView(log: log)))
        window.title = "Activity – \(repository.workTree.lastPathComponent)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        // Named when this was the Git log window, and kept so the place it was left still applies.
        RememberedWindowPlacement(autosaveName: "GitLog").apply(to: window, initialContentSize: NSSize(width: 760, height: 480))
        return window
    }
}
