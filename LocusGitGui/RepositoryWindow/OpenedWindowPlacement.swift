import AppKit

/// Where a window opened from a repository's window goes: where it was left, while that's still on
/// a screen, and otherwise cascaded from the window it was opened from, so it's clear which
/// repository it came from.
enum OpenedWindowPlacement {
    static func place(_ window: NSWindow, at frame: String?, cascadingFrom source: NSWindow?) {
        if let frame {
            window.setFrame(from: frame)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
                return
            }
        }
        guard let source else {
            window.center()
            return
        }
        let topLeft = window.cascadeTopLeft(from: NSPoint(x: source.frame.minX, y: source.frame.maxY))
        window.cascadeTopLeft(from: topLeft)
    }
}
