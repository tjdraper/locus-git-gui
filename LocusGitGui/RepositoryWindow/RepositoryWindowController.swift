import AppKit

/// The window for one repository.
final class RepositoryWindowController: NSWindowController {
    let repository: URL

    init(repository: URL) {
        self.repository = repository
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = (repository.path as NSString).abbreviatingWithTildeInPath
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }
}
