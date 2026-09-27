import AppKit

/// How fetching behaves, for every repository: whether Fetch prunes and fetches every tag, and
/// whether windows fetch by themselves now and then. Set from the Remote menu and the menu on the
/// toolbar's Fetch button. Settings gains the automatic fetch's interval in slice 13.
final class FetchPreferences: NSObject, NSMenuItemValidation {
    static let automaticFetchDidChange = Notification.Name("FetchPreferencesAutomaticFetchDidChange")
    private static let automaticKey = "FetchesAutomatically"
    private static let pruneKey = "FetchPrunes"
    private static let tagsKey = "FetchIncludesTags"

    /// For the Remote menu.
    private(set) var menuItems: [NSMenuItem] = []
    /// Fetch without the options, with only pruning, and with only tags, for the Remote menu after
    /// Fetch. Whichever does just what Fetch does is hidden, and with it left out of the palette.
    let variantItems: [NSMenuItem]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        variantItems = [AppCommand.fetchWithoutOptions, .fetchAndPrune, .fetchWithTags].map { $0.makeMenuItem() }
        super.init()
        menuItems = [AppCommand.prunesWhenFetching, .fetchesTagsWhenFetching, .fetchAutomatically].map { $0.makeMenuItem(target: self) }
        hideVariantSameAsFetch()
    }

    var fetchesAutomatically: Bool {
        defaults.bool(forKey: Self.automaticKey)
    }

    /// What Fetch adds to `git fetch`.
    var options: FetchOptions {
        FetchOptions(prunes: defaults.bool(forKey: Self.pruneKey), fetchesTags: defaults.bool(forKey: Self.tagsKey))
    }

    /// For the menu on the toolbar's Fetch button. A new one each time, since a menu item belongs
    /// to one menu and every repository window has a toolbar.
    func makeOptionsMenu() -> NSMenu {
        let menu = NSMenu()
        for command in [AppCommand.prunesWhenFetching, .fetchesTagsWhenFetching] {
            menu.addItem(command.makeMenuItem(target: self))
        }
        return menu
    }

    @objc func toggleAutomaticFetch(_: Any?) {
        defaults.set(!fetchesAutomatically, forKey: Self.automaticKey)
        NotificationCenter.default.post(name: Self.automaticFetchDidChange, object: self)
    }

    @objc func togglePruneWhenFetching(_: Any?) {
        defaults.set(!options.prunes, forKey: Self.pruneKey)
        hideVariantSameAsFetch()
    }

    @objc func toggleTagsWhenFetching(_: Any?) {
        defaults.set(!options.fetchesTags, forKey: Self.tagsKey)
        hideVariantSameAsFetch()
    }

    private func hideVariantSameAsFetch() {
        let variants: [FetchOptions] = [FetchOptions(), .prune, .tags]
        for (item, variant) in zip(variantItems, variants) {
            item.isHidden = variant == options
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let isOn = switch menuItem.action {
        case #selector(toggleAutomaticFetch(_:)): fetchesAutomatically
        case #selector(togglePruneWhenFetching(_:)): options.prunes
        case #selector(toggleTagsWhenFetching(_:)): options.fetchesTags
        default: false
        }
        menuItem.state = isOn ? .on : .off
        return true
    }
}
