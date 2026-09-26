import AppKit

/// The working area in a window of its own: the message, the filter and every change, as the
/// detail column shows them. It shares the column's message, so what's written in one shows in both.
final class WorkingAreaWindowController: NSWindowController, NSWindowDelegate {
    private static let contentSize = NSSize(width: 900, height: 800)

    let workingArea: WorkingAreaViewController
    var onClose: (() -> Void)?

    init(workingArea: WorkingAreaViewController, repositoryName: String) {
        self.workingArea = workingArea
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Brought back with its repository's window, rather than on its own after a relaunch.
        window.isRestorable = false
        // Kept apart from repository windows, which would otherwise take it as a tab.
        window.tabbingIdentifier = "WorkingAreaWindow"
        window.title = WorkingAreaRowView.title
        window.subtitle = repositoryName
        // Gives the title bar room for the subtitle.
        window.toolbar = NSToolbar(identifier: "WorkingAreaWindow")
        window.toolbarStyle = .unified
        super.init(window: window)
        window.contentViewController = workingArea
        window.setContentSize(Self.contentSize)
        window.delegate = self
        workingArea.setShown(true)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func windowWillClose(_: Notification) {
        workingArea.setShown(false)
        onClose?()
    }

    /// The working area's and the diff's commands reach them wherever focus is in the window.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if WorkingAreaViewController.windowActions.contains(action) {
            return workingArea
        }
        if DiffViewController.windowActions.contains(action) {
            return workingArea.diff
        }
        return super.supplementalTarget(forAction: action, sender: sender)
    }
}
