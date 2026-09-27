import AppKit

/// A history window's two columns: the history, and the detail of the commit it has selected.
final class HistorySplitViewController: NSSplitViewController {
    private static let historyWidth: CGFloat = 400

    private let historyItem: NSSplitViewItem
    private let detailItem: NSSplitViewItem
    private var hasPlacedDivider = false

    init(history: NSViewController, detail: NSViewController) {
        historyItem = NSSplitViewItem(contentListWithViewController: history)
        historyItem.minimumThickness = 280
        detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 320
        // The detail column takes up a change in the window's width.
        historyItem.holdingPriority = .init(255)
        detailItem.holdingPriority = .init(250)
        super.init(nibName: nil, bundle: nil)
        addSplitViewItem(historyItem)
        addSplitViewItem(detailItem)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// Once the window has its frame, as the repository window's columns are.
    override func viewWillAppear() {
        super.viewWillAppear()
        guard !hasPlacedDivider else { return }
        splitView.layoutSubtreeIfNeeded()
        splitView.setPosition(Self.historyWidth, ofDividerAt: 0)
        hasPlacedDivider = true
    }
}
