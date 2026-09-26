import AppKit
import SwiftUI

/// The Activity window for one repository, opened from View > Show Activity or the toolbar's
/// activity indicator.
final class ActivityWindowPresenter {
    private let log: GitCommandLog
    private var repositoryName: String
    private var window: NSWindow?

    init(log: GitCommandLog, repositoryName: String) {
        self.log = log
        self.repositoryName = repositoryName
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func showRepositoryName(_ name: String) {
        repositoryName = name
        window?.subtitle = name
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: ActivityView(log: log)))
        window.title = "Activity"
        window.subtitle = repositoryName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Gives the title bar room for the subtitle.
        window.toolbar = NSToolbar(identifier: "ActivityWindow")
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        // Named when this was the Git log window, and kept so the place it was left still applies.
        RememberedWindowPlacement(autosaveName: "GitLog").apply(to: window, initialContentSize: NSSize(width: 760, height: 480))
        return window
    }
}
