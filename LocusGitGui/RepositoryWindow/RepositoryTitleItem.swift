import AppKit
import SwiftUI

/// The title in the toolbar, standing in for AppKit's, with a folder icon in place of the proxy
/// icon the hidden title takes with it: drag the folder out, or ⌘-click the title for its path.
final class RepositoryTitleItem: NSObject {
    static let identifier = NSToolbarItem.Identifier("RepositoryTitle")

    /// Past this, the toolbar moves the title into its overflow menu rather than cut it further.
    private static let minimumWidth: CGFloat = 120
    /// Inside the glass the toolbar draws behind the item.
    private static let horizontalPadding: CGFloat = 10

    let title: RepositoryTitle
    private let folder: URL
    private lazy var container = makeContainer()
    /// Kept here because a menu holds its items' target only weakly.
    private lazy var pathMenu = RepositoryPathMenu(folder: folder)
    /// Stands in for the title in the toolbar's overflow menu, where a view can't go.
    private lazy var overflowItem = makeOverflowItem()

    init(repository: Repository, displayName: String?) {
        folder = repository.workTree
        title = RepositoryTitle(path: (folder.path as NSString).abbreviatingWithTildeInPath, displayName: displayName)
    }

    func makeItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.identifier)
        item.label = "Title"
        item.view = container
        item.menuFormRepresentation = overflowItem
        item.visibilityPriority = .user
        return item
    }

    func setDisplayName(_ displayName: String?) {
        title.displayName = displayName
        overflowItem.title = displayName ?? folder.lastPathComponent
    }

    /// True when the click was on the title and the menu was shown.
    func showPathMenu(for event: NSEvent) -> Bool {
        guard container.window != nil else { return false }
        let point = container.convert(event.locationInWindow, from: nil)
        guard container.bounds.contains(point) else { return false }
        pathMenu.popUp(at: point, in: container)
        return true
    }

    private func makeContainer() -> NSView {
        let container = NSView()
        let icon = RepositoryFolderIcon(folder: folder)
        let text = MovableHostingView(rootView: RepositoryTitleView(title: title))
        // At the default priority the toolbar keeps the title at its full width and moves it into
        // the overflow menu rather than cut the path. Below `fittingSize`'s own priority, it shrinks.
        text.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        text.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        for view in [icon, text] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.horizontalPadding),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            text.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.horizontalPadding),
            text.topAnchor.constraint(equalTo: container.topAnchor),
            text.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth),
        ])
        return container
    }

    private func makeOverflowItem() -> NSMenuItem {
        let item = NSMenuItem(title: title.displayName ?? folder.lastPathComponent, action: nil, keyEquivalent: "")
        item.submenu = pathMenu.makeMenu()
        return item
    }
}

/// Lets the window be dragged, and double-clicked to zoom, by its title, as AppKit's own title can.
private final class MovableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}

/// The repository's folder, dragged out as AppKit's proxy icon is: to Finder, Terminal, or any app
/// that takes a folder.
private final class RepositoryFolderIcon: NSView, NSDraggingSource {
    private static let size = NSSize(width: 16, height: 16)

    private let folder: URL
    private let image: NSImage
    private var dragStarted = false

    init(folder: URL) {
        self.folder = folder
        image = NSWorkspace.shared.icon(forFile: folder.path)
        image.size = Self.size
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Repository folder")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        Self.size
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func draw(_: NSRect) {
        image.draw(in: bounds)
    }

    /// Taken here so the click doesn't pass on to the title bar, which would move the window.
    override func mouseDown(with _: NSEvent) {
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted else { return }
        dragStarted = true
        let item = NSDraggingItem(pasteboardWriter: folder as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    /// Never a move, which would take the repository out from under the window showing it.
    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        [.copy, .link, .generic]
    }
}
