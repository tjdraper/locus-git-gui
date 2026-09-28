import AppKit

/// How fetching behaves, for every repository: whether Fetch prunes and fetches every tag, and
/// whether windows fetch by themselves now and then, and how often. Set from the Remote menu, the
/// menu on the toolbar's Fetch button and Settings.
@Observable
final class FetchPreferences: NSObject, NSMenuItemValidation {
    static let automaticFetchDidChange = Notification.Name("FetchPreferencesAutomaticFetchDidChange")
    /// The choices Settings offers, in minutes.
    static let automaticIntervals = [1, 5, 10, 15, 30, 60]
    private static let defaultInterval = 5
    private static let automaticKey = "FetchesAutomatically"
    private static let intervalKey = "AutomaticFetchMinutes"
    private static let pruneKey = "FetchPrunes"
    private static let tagsKey = "FetchIncludesTags"

    /// For the Remote menu.
    @ObservationIgnored private(set) var menuItems: [NSMenuItem] = []
    /// Fetch without the options, with only pruning, and with only tags, for the Remote menu after
    /// Fetch. Whichever does just what Fetch does is hidden, and with it left out of the palette.
    @ObservationIgnored let variantItems: [NSMenuItem]
    @ObservationIgnored private let defaults: UserDefaults

    var fetchesAutomatically: Bool {
        didSet {
            defaults.set(fetchesAutomatically, forKey: Self.automaticKey)
            NotificationCenter.default.post(name: Self.automaticFetchDidChange, object: self)
        }
    }

    var automaticIntervalMinutes: Int {
        didSet {
            defaults.set(automaticIntervalMinutes, forKey: Self.intervalKey)
            NotificationCenter.default.post(name: Self.automaticFetchDidChange, object: self)
        }
    }

    /// What Fetch adds to `git fetch`.
    var options: FetchOptions {
        didSet {
            defaults.set(options.prunes, forKey: Self.pruneKey)
            defaults.set(options.fetchesTags, forKey: Self.tagsKey)
            hideVariantSameAsFetch()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fetchesAutomatically = defaults.bool(forKey: Self.automaticKey)
        let interval = defaults.integer(forKey: Self.intervalKey)
        automaticIntervalMinutes = Self.automaticIntervals.contains(interval) ? interval : Self.defaultInterval
        options = FetchOptions(prunes: defaults.bool(forKey: Self.pruneKey), fetchesTags: defaults.bool(forKey: Self.tagsKey))
        variantItems = [AppCommand.fetchWithoutOptions, .fetchAndPrune, .fetchWithTags].map { $0.makeMenuItem() }
        super.init()
        menuItems = [AppCommand.prunesWhenFetching, .fetchesTagsWhenFetching, .fetchAutomatically].map { $0.makeMenuItem(target: self) }
        hideVariantSameAsFetch()
    }

    var automaticInterval: Duration {
        .seconds(automaticIntervalMinutes * 60)
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
        fetchesAutomatically.toggle()
    }

    @objc func togglePruneWhenFetching(_: Any?) {
        options.prunes.toggle()
    }

    @objc func toggleTagsWhenFetching(_: Any?) {
        options.fetchesTags.toggle()
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
