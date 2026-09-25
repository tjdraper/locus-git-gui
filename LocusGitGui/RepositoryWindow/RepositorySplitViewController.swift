import AppKit

/// The window's three columns: the sidebar, the history of what it has selected, and the detail of
/// what the history has selected.
final class RepositorySplitViewController: NSSplitViewController {
    private static let defaultColumns = RepositoryViewState.Columns(sidebarWidth: 220, historyWidth: 400, isSidebarCollapsed: false)

    var onColumnsChange: (() -> Void)?
    private let sidebarItem: NSSplitViewItem
    private let historyItem: NSSplitViewItem
    private let detailItem: NSSplitViewItem
    private let initialColumns: RepositoryViewState.Columns
    private var sidebarWidth: Double
    /// Resizes during the first layout are AppKit fitting the columns to the window, not the user.
    private var hasAppliedColumns = false

    init(sidebar: NSViewController, history: NSViewController, detail: NSViewController, columns: RepositoryViewState.Columns?) {
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 400
        historyItem = NSSplitViewItem(contentListWithViewController: history)
        historyItem.minimumThickness = 280
        detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 320
        // The detail column takes up a change in the window's width, and the sidebar gives last.
        sidebarItem.holdingPriority = .init(260)
        historyItem.holdingPriority = .init(255)
        detailItem.holdingPriority = .init(250)
        initialColumns = columns ?? Self.defaultColumns
        sidebarWidth = initialColumns.sidebarWidth
        super.init(nibName: nil, bundle: nil)
        for item in [sidebarItem, historyItem, detailItem] {
            addSplitViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var columns: RepositoryViewState.Columns {
        guard hasAppliedColumns else { return initialColumns }
        return RepositoryViewState.Columns(
            sidebarWidth: sidebarWidth,
            historyWidth: historyItem.viewController.view.frame.width,
            isSidebarCollapsed: sidebarItem.isCollapsed
        )
    }

    func showSidebar() {
        guard sidebarItem.isCollapsed else { return }
        sidebarItem.animator().isCollapsed = false
    }

    /// Once the window has its frame, which restoring it after a relaunch sets only after it's made.
    override func viewWillAppear() {
        super.viewWillAppear()
        guard !hasAppliedColumns else { return }
        splitView.layoutSubtreeIfNeeded()
        splitView.setPosition(initialColumns.sidebarWidth, ofDividerAt: 0)
        // From where the history column starts, since the sidebar's divider is thinner than
        // `dividerThickness` says, and adding that would widen the column a little every reopen.
        let historyStart = historyItem.viewController.view.convert(NSPoint.zero, to: splitView).x
        splitView.setPosition(historyStart + initialColumns.historyWidth, ofDividerAt: 1)
        sidebarItem.isCollapsed = initialColumns.isSidebarCollapsed
        hasAppliedColumns = true
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard hasAppliedColumns else { return }
        if !sidebarItem.isCollapsed {
            sidebarWidth = sidebarItem.viewController.view.frame.width
        }
        onColumnsChange?()
    }
}
