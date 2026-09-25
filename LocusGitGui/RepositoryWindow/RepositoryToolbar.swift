import AppKit

/// The repository window's toolbar, customizable the usual way. It holds the sidebar button, the
/// title, and the quiet warning for a failure the user didn't ask for, such as a background refresh,
/// which never interrupts with a sheet.
final class RepositoryToolbar: NSObject, NSToolbarDelegate {
    private static let warningIdentifier = NSToolbarItem.Identifier("GitFailureWarning")

    let toolbar = NSToolbar(identifier: "RepositoryWindow")
    private let title: RepositoryTitleItem
    private let showDetails: () -> Void
    private var warningItem: NSToolbarItem?

    init(title: RepositoryTitleItem, showDetails: @escaping () -> Void) {
        self.title = title
        self.showDetails = showDetails
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
    }

    func showWarning(_ summary: String) {
        warningItem?.toolTip = "\(summary) Click for details."
        warningItem?.isHidden = false
    }

    func hideWarning() {
        warningItem?.isHidden = true
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, RepositoryTitleItem.identifier, .flexibleSpace, Self.warningIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            RepositoryTitleItem.identifier,
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
