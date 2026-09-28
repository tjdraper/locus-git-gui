import AppKit
import SwiftUI

/// The toolbar's place for `ToolbarStatus`, just after the title, so a status coming and going never
/// moves the history or the commit below it. It keeps one width whatever it shows, so it doesn't
/// grow and shrink under the eye either, until there's no room for its text. Then it becomes an icon
/// and gives the room to the title. A click opens the Notices panel, pointing at it, and a click on
/// the spinner while Git works opens the Activity window.
final class ToolbarStatusItem: NSObject {
    static let identifier = NSToolbarItem.Identifier("Status")

    private static let minimumWidth: CGFloat = 44
    /// The icon and a count beside it.
    private static let compactWidth: CGFloat = 72
    /// The toolbar shares out spare width equally between the items that can use it, so a wider
    /// status would take as much from the title as it gains.
    private static let width: CGFloat = 380
    /// How much more room there has to be than when it became an icon before it shows its text
    /// again, so it doesn't switch back and forth at one width.
    private static let widening: CGFloat = 40

    enum Opening {
        case notices
        case activity
    }

    private let status: ToolbarStatus
    private let title: RepositoryTitleItem
    private let activity: GitActivity
    private let open: (Opening) -> Void
    private weak var item: NSToolbarItem?
    private weak var view: NSHostingView<ToolbarStatusView>?
    private var compactConstraint: NSLayoutConstraint?
    /// The room right of the sidebar when it became an icon. Nil while it shows its text.
    private var compactAt: CGFloat?
    private var watches: [NotificationWatch] = []
    private lazy var panel = makePanel()
    /// Stands in for the status in the toolbar's overflow menu, where a view can't go.
    private lazy var overflowItem = NSMenuItem(title: "", action: #selector(showPanelFromMenu(_:)), keyEquivalent: "")

    init(status: ToolbarStatus, title: RepositoryTitleItem, log: GitCommandLog, open: @escaping (Opening) -> Void) {
        self.status = status
        self.title = title
        activity = GitActivity(log: log)
        self.open = open
        super.init()
        follow()
    }

    func makeItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.identifier)
        item.label = "Status"
        item.paletteLabel = "Status"
        let view = NSHostingView(rootView: makeContent(isCompact: false))
        view.sizingOptions = [.intrinsicContentSize]
        view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        // Below `fittingSize`'s own priority, so a narrow window can still cut it down to the minimum.
        let preferred = view.widthAnchor.constraint(equalToConstant: Self.width)
        preferred.priority = .init(40)
        NSLayoutConstraint.activate([
            preferred,
            view.widthAnchor.constraint(lessThanOrEqualToConstant: Self.width),
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth),
        ])
        compactConstraint = view.widthAnchor.constraint(lessThanOrEqualToConstant: Self.compactWidth)
        view.postsFrameChangedNotifications = true
        watches = [
            NotificationWatch(NSView.frameDidChangeNotification, object: view) { [weak self] in self?.fitContent() },
            // Covers growing back, when the icon keeps one width while the window widens.
            NotificationWatch(NSWindow.didResizeNotification) { [weak self] in self?.fitContent() },
        ]
        item.view = view
        overflowItem.target = self
        item.menuFormRepresentation = overflowItem
        item.visibilityPriority = .high
        self.item = item
        self.view = view
        update()
        return item
    }

    private func makeContent(isCompact: Bool) -> ToolbarStatusView {
        ToolbarStatusView(
            status: status,
            activity: activity,
            isCompact: isCompact,
            openPanel: { [weak self] in self?.togglePanel() },
            showActivity: { [weak self] in self?.open(.activity) }
        )
    }

    /// The toolbar decides how wide the status is from how wide the window is, so it can't size to
    /// its content. It becomes an icon when it's given too little for its text, and shows the text
    /// again once there's clearly more room than there was then.
    private func fitContent() {
        guard let view, let window = view.window, let leading = title.leadingEdgeInWindow else { return }
        let room = window.frame.width - leading
        if let compactAt {
            guard room > compactAt + Self.widening else { return }
            setCompact(false)
        } else if view.frame.width < ToolbarStatusView.fullWidth(for: status.latest) {
            compactAt = room
            setCompact(true)
        }
    }

    private func setCompact(_ isCompact: Bool) {
        if !isCompact {
            compactAt = nil
        }
        compactConstraint?.isActive = isCompact
        view?.rootView = makeContent(isCompact: isCompact)
    }

    private func togglePanel() {
        if panel.isShown {
            panel.performClose(nil)
            return
        }
        guard let view, view.window != nil else { return }
        panel.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    @objc private func showPanelFromMenu(_: Any?) {
        open(.notices)
    }

    private func makePanel() -> NSPopover {
        let panel = NSPopover()
        panel.behavior = .transient
        let controller = NSHostingController(rootView: NoticesView(status: status) { [weak self] in
            self?.panel.performClose(nil)
            self?.open(.notices)
        })
        controller.sizingOptions = .preferredContentSize
        panel.contentViewController = controller
        return panel
    }

    private func update() {
        overflowItem.title = status.latest.flatMap(status.summary(of:)) ?? status.idleSummary(at: .now) ?? "Notices"
    }

    private func follow() {
        withObservationTracking {
            _ = status.latest
            _ = status.latest.flatMap(status.summary(of:))
            _ = status.idleSummary(at: .now)
        } onChange: { [weak self] in
            // Called before the change is made, so the status is read once it has been.
            Task { @MainActor in
                self?.update()
                // What it shows can need more room than what it showed.
                self?.fitContent()
                self?.follow()
            }
        }
    }
}
