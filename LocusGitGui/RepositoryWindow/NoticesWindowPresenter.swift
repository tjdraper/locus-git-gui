import AppKit
import SwiftUI

/// The Notices window for one repository, opened from View > Show Notices or the Notices panel.
final class NoticesWindowPresenter {
    private let status: ToolbarStatus
    private var repositoryName: String
    private var window: NSWindow?
    /// When the window opens or closes, for the repository to remember.
    var onChange: (() -> Void)?

    var isShown: Bool {
        window?.isVisible == true
    }

    init(status: ToolbarStatus, repositoryName: String) {
        self.status = status
        self.repositoryName = repositoryName
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        onChange?()
    }

    func close() {
        window?.close()
    }

    func showRepositoryName(_ name: String) {
        repositoryName = name
        window?.subtitle = name
    }

    private func makeWindow() -> NSWindow {
        let content = NSHostingController(rootView: NoticesView(status: status, openWindow: nil))
        // The notices fill whatever size the window is given, so they don't size the window, which
        // would otherwise grow to their unlimited height.
        content.sizingOptions = []
        let window = NSWindow(contentViewController: content)
        window.contentMinSize = NSSize(width: 320, height: 200)
        window.title = "Notices"
        window.subtitle = repositoryName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Gives the title bar room for the subtitle.
        window.toolbar = NSToolbar(identifier: "NoticesWindow")
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        RememberedWindowPlacement(autosaveName: "Notices").apply(to: window, initialContentSize: NSSize(width: 420, height: 360))
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification, object: window) {
                // Still visible while it closes.
                DispatchQueue.main.async { self?.onChange?() }
            }
        }
        return window
    }
}
