import AppKit

/// The repository window's toolbar, customizable the usual way. It holds the sidebar button, the
/// title, Fetch, Pull and Push, the activity indicator, and the quiet warning for a failure the
/// user didn't ask for, such as a background refresh, which never interrupts with a sheet.
final class RepositoryToolbar: NSObject, NSToolbarDelegate {
    private static let warningIdentifier = NSToolbarItem.Identifier("GitFailureWarning")
    private static let offeredItemsKey = "RepositoryToolbarOfferedItems"
    /// The items the toolbar had before `offerNewItems` kept track, which every saved layout has
    /// already been offered.
    private static let firstItems: [NSToolbarItem.Identifier] = [
        .toggleSidebar, .sidebarTrackingSeparator, RepositoryTitleItem.identifier, .flexibleSpace, warningIdentifier,
    ]

    /// Titled and reaching their commands as the Remote menu's items do.
    private static let commands: [AppCommand] = [.fetch, .pull, .push]

    let toolbar = NSToolbar(identifier: "RepositoryWindow")
    private let title: RepositoryTitleItem
    /// Fetch's options, which a menu on its button sets.
    private let fetchOptions: NSMenu
    private let activity: ActivityIndicator
    private let showDetails: () -> Void
    private var warningItem: NSToolbarItem?
    private var commandItems: [AppCommand: NSToolbarItem] = [:]
    /// The checked-out branch's commits to push and to pull, shown on Push and Pull.
    private var tracking: (ahead: Int, behind: Int) = (0, 0)

    init(title: RepositoryTitleItem, fetchOptions: NSMenu, activity: ActivityIndicator, showDetails: @escaping () -> Void) {
        self.title = title
        self.fetchOptions = fetchOptions
        self.activity = activity
        self.showDetails = showDetails
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
    }

    func attach(to window: NSWindow) {
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        offerNewItems()
    }

    /// AppKit only uses the default items for a toolbar with no saved layout, so an item added in a
    /// later version never appears in one saved before it. Each new item is put in once, before the
    /// activity indicator or the warning, and remembered, so an item the user takes out in Customize
    /// Toolbar stays out. Called once the toolbar is in a window, which is when it reads its saved
    /// layout.
    private func offerNewItems(defaults: UserDefaults = .standard) {
        let offered = defaults.stringArray(forKey: Self.offeredItemsKey).map { Set($0.map { NSToolbarItem.Identifier(rawValue: $0) }) }
            ?? Set(Self.firstItems)
        let defaultItems = toolbarDefaultItemIdentifiers(toolbar)
        for identifier in defaultItems where !offered.contains(identifier) {
            guard !toolbar.items.contains(where: { $0.itemIdentifier == identifier }) else { continue }
            let following = toolbar.items.firstIndex { [ActivityIndicator.identifier, Self.warningIdentifier].contains($0.itemIdentifier) }
            toolbar.insertItem(withItemIdentifier: identifier, at: following ?? toolbar.items.count)
        }
        defaults.set(offered.union(defaultItems).map(\NSToolbarItem.Identifier.rawValue).sorted(), forKey: Self.offeredItemsKey)
    }

    /// `summary` is the failure's when there's one, and a count shows when there are more.
    func showWarning(_ summary: String, count: Int) {
        warningItem?.toolTip = count > 1 ? "\(count) things went wrong. Click for details." : "\(summary) Click for details."
        warningItem?.badge = count > 1 ? .count(count) : nil
        warningItem?.isHidden = false
    }

    /// Nothing when there's nothing to push or pull.
    func showTracking(ahead: Int, behind: Int) {
        tracking = (ahead, behind)
        commandItems[.push]?.badge = ahead > 0 ? .count(ahead) : nil
        commandItems[.pull]?.badge = behind > 0 ? .count(behind) : nil
    }

    func hideWarning() {
        warningItem?.isHidden = true
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            RepositoryTitleItem.identifier,
            .flexibleSpace,
        ] + Self.commands.map(\.toolbarIdentifier) + [
            ActivityIndicator.identifier,
            Self.warningIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            RepositoryTitleItem.identifier,
        ] + Self.commands.map(\.toolbarIdentifier) + [
            ActivityIndicator.identifier,
            .flexibleSpace,
            .space,
            Self.warningIdentifier,
        ]
    }

    /// The title has nowhere else to go, and a warning that could be removed would hide failures.
    func toolbarImmovableItemIdentifiers(_: NSToolbar) -> Set<NSToolbarItem.Identifier> {
        [.sidebarTrackingSeparator, RepositoryTitleItem.identifier, Self.warningIdentifier]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        if identifier == RepositoryTitleItem.identifier {
            return title.makeItem()
        }
        if identifier == ActivityIndicator.identifier {
            return activity.makeItem()
        }
        if let command = Self.commands.first(where: { $0.toolbarIdentifier == identifier }) {
            return makeItem(for: command)
        }
        guard identifier == Self.warningIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Git Problem"
        // The full-colour symbol, a solid yellow triangle with a dark mark, stands out in both
        // appearances where a single tint washes out against a light toolbar.
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Git problem")?
            .withSymbolConfiguration(.preferringMulticolor())
        item.isBordered = true
        item.target = self
        item.action = #selector(warningClicked(_:))
        item.isHidden = true
        warningItem = item
        return item
    }

    @objc private func warningClicked(_: Any?) {
        showDetails()
    }

    /// Sent up the responder chain like the menu item, which also decides whether it's enabled.
    /// Fetch's button has a menu of its options beside it.
    private func makeItem(for command: AppCommand) -> NSToolbarItem {
        let item: NSToolbarItem
        if command == .fetch {
            let menuItem = NSMenuToolbarItem(itemIdentifier: command.toolbarIdentifier)
            menuItem.menu = fetchOptions
            menuItem.showsIndicator = true
            item = menuItem
        } else {
            item = NSToolbarItem(itemIdentifier: command.toolbarIdentifier)
        }
        item.label = command.title
        item.paletteLabel = command.title
        item.toolTip = command.shortcut.map { "\(command.title) (\($0.displayText))" } ?? command.title
        item.image = NSImage(systemSymbolName: Self.symbol(for: command), accessibilityDescription: command.title)
        item.isBordered = true
        item.action = command.action
        commandItems[command] = item
        showTracking(ahead: tracking.ahead, behind: tracking.behind)
        return item
    }

    private static func symbol(for command: AppCommand) -> String {
        switch command {
        case .pull: "arrow.down.to.line"
        case .push: "arrow.up.to.line"
        default: "arrow.trianglehead.2.clockwise"
        }
    }
}

extension AppCommand {
    fileprivate var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }
}
