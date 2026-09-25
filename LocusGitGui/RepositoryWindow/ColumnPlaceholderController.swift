import AppKit

/// Holds the history and detail columns' places until the views that fill them exist.
final class ColumnPlaceholderController: NSViewController {
    override func loadView() {
        view = NSView()
    }
}
