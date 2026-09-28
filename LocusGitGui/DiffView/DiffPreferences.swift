import AppKit

/// How every diff is shown, set in Settings: side by side or inline, the font, and the options a
/// repository starts with until it's given its own from the View menu.
nonisolated struct DiffPreferences {
    /// Posted after any of them change, for every diff shown to follow.
    static let didChange = Notification.Name("DiffPreferencesDidChange")

    enum Layout: String, CaseIterable, Sendable {
        /// Side by side when the diff has room for both versions, and inline when it doesn't.
        case automatic
        case sideBySide
        case inline
    }

    static let fontSizes: ClosedRange<Double> = 9 ... 24
    static let defaultFontSize = 11.0

    private static let layoutKey = "DiffLayout"
    private static let fontFamilyKey = "DiffFontFamily"
    private static let fontSizeKey = "DiffFontSize"
    private static let ignoresWhitespaceKey = "DiffIgnoresWhitespace"
    private static let contextLinesKey = "DiffContextLines"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var layout: Layout {
        get { defaults.string(forKey: Self.layoutKey).flatMap(Layout.init) ?? .automatic }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.layoutKey) }
    }

    /// Nil for the system's fixed-width font.
    var fontFamily: String? {
        get { defaults.string(forKey: Self.fontFamilyKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.fontFamilyKey) }
    }

    var fontSize: Double {
        get {
            let size = defaults.double(forKey: Self.fontSizeKey)
            return size == 0 ? Self.defaultFontSize : min(max(size, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        }
        nonmutating set { defaults.set(newValue, forKey: Self.fontSizeKey) }
    }

    var font: NSFont {
        Self.font(family: fontFamily, size: fontSize)
    }

    /// A family that's been uninstalled since it was chosen gives way to the system's font.
    static func font(family: String?, size: Double) -> NSFont {
        if let family, let font = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size),
           font.familyName == family {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var defaultOptions: DiffOptions {
        get {
            var options = DiffOptions()
            options.ignoresWhitespace = defaults.bool(forKey: Self.ignoresWhitespaceKey)
            if let contextLines = defaults.object(forKey: Self.contextLinesKey) as? Int, DiffOptions.contextSteps.contains(contextLines) {
                options.contextLines = contextLines
            }
            return options
        }
        nonmutating set {
            defaults.set(newValue.ignoresWhitespace, forKey: Self.ignoresWhitespaceKey)
            defaults.set(newValue.contextLines, forKey: Self.contextLinesKey)
        }
    }
}
