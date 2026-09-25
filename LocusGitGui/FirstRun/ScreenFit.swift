import AppKit

/// How tall the checklist can grow before its window runs off the screen. The window can't be
/// resized, so without a limit a small screen leaves Done out of reach below the bottom edge.
@Observable
final class ScreenFit {
    private(set) var maxContentHeight = CGFloat.infinity

    /// A window that has not been shown yet has no screen, and it opens on the primary display.
    func update(for window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.screens.first else { return }
        let titleBarHeight = window.frameRect(forContentRect: .zero).height
        maxContentHeight = screen.visibleFrame.height - titleBarHeight
    }

    /// A step that gains rows grows the window downward from where it was placed. The Git step
    /// fills in only after the search for Git finishes, which can push the bottom under the Dock.
    func keepOnScreen(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.screens.first)?.visibleFrame else { return }
        var origin = window.frame.origin
        origin.y = max(origin.y, visible.minY)
        origin.y = min(origin.y, visible.maxY - window.frame.height)
        guard origin != window.frame.origin else { return }
        window.setFrameOrigin(origin)
    }
}
