import AppKit
import SwiftUI

/// The Git log window for one repository, opened from View > Show Git Log.
final class GitLogWindowPresenter {
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
        let window = NSWindow(contentViewController: NSHostingController(rootView: GitLogView(log: log)))
        window.title = "Git Log – \(repository.workTree.lastPathComponent)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 480))
        window.center()
        return window
    }
}
