import Foundation

/// Which path ⌥⌘C copies: the absolute path, as it does to begin with, or the path from the
/// repository root. The other Copy Path command takes ⌥⇧⌘C.
nonisolated struct CopyPathShortcutPreference {
    private static let defaultsKey = "OptionCommandCCopiesPathFromRoot"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var copiesPathFromRoot: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }
}
