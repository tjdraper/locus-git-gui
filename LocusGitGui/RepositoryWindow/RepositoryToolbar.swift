import AppKit

/// The repository window's toolbar, customizable the usual way. It holds the sidebar button, the
/// title, the activity indicator, and the quiet warning for a failure the user didn't ask for, such
/// as a background refresh, which never interrupts with a sheet.
final class RepositoryToolbar: NSObject, NSToolbarDelegate {
    private static let warningIdentifier = NSToolbarItem.Identifier("GitFailureWarning")
    private static let offeredItemsKey = "RepositoryToolbarOfferedItems"
    /// The items the toolbar had before `offerNewItems` kept track, which every saved layout has
    /// already been offered.
    private static let firstItems: [NSToolbarItem.Identifier] = [
        .toggleSidebar, .sidebarTrackingSeparator, RepositoryTitleItem.identifier, .flexibleSpace, warningIdentifier,
    ]

    let toolbar = NSToolbar(identifier: "RepositoryWindow")
    private let title: RepositoryTitleItem
    private let activity: ActivityIndicator
    private let showDetails: () -> Void
    private var warningItem: NSToolbarItem?

    init(title: RepositoryTitleItem, activity: ActivityIndicator, showDetails: @escaping () -> Void) {
        self.title = title
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
    /// warning, and remembered, so an item the user takes out in Customize Toolbar stays out. Called
    /// once the toolbar is in a window, which is when it reads its saved layout.
    private func offerNewItems(defaults: UserDefaults = .standard) {
        let offered = defaults.stringArray(forKey: Self.offeredItemsKey).map { Set($0.map { NSToolbarItem.Identifier(rawValue: $0) }) }
            ?? Set(Self.firstItems)
        let defaultItems = toolbarDefaultItemIdentifiers(toolbar)
        for identifier in defaultItems where !offered.contains(identifier) {
            guard !toolbar.items.contains(where: { $0.itemIdentifier == identifier }) else { continue }
            let warning = toolbar.items.firstIndex { $0.itemIdentifier == Self.warningIdentifier }
            toolbar.insertItem(withItemIdentifier: identifier, at: warning ?? toolbar.items.count)
        }
        defaults.set(offered.union(defaultItems).map(\NSToolbarItem.Identifier.rawValue).sorted(), forKey: Self.offeredItemsKey)
    }

    func showWarning(_ summary: String) {
        warningItem?.toolTip = "\(summary) Click for details."
        warningItem?.isHidden = false
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
            ActivityIndicator.identifier,
            Self.warningIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            RepositoryTitleItem.identifier,
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
}
