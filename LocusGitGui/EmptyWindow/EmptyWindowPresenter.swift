import AppKit

/// Stands in for the repository windows until the app can open a repository, so the release
/// pipeline has a window to show.
final class EmptyWindowPresenter {
    private lazy var window = makeWindow()

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Locus Git Gui"
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
