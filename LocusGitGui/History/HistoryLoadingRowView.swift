import AppKit

/// The last row of a history that has more to read: the same small spinner the column shows while
/// its first commits are read.
final class HistoryLoadingRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryLoadingRow")

    private let spinner = NSProgressIndicator()

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Loading more commits")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// Spinning only while it's in a window, since a row the table keeps for reuse would otherwise
    /// go on animating out of sight.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            spinner.stopAnimation(nil)
        } else {
            spinner.startAnimation(nil)
        }
    }
}
