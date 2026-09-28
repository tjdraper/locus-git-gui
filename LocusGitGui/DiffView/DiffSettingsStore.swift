import AppKit

/// Settings' copy of `DiffPreferences`, which saves each change and tells every diff shown.
@Observable
final class DiffSettingsStore {
    var layout: DiffPreferences.Layout {
        didSet { save { $0.layout = layout } }
    }

    var fontFamily: String? {
        didSet { save { $0.fontFamily = fontFamily } }
    }

    var fontSize: Double {
        didSet { save { $0.fontSize = fontSize } }
    }

    var defaultOptions: DiffOptions {
        didSet { save { $0.defaultOptions = defaultOptions } }
    }

    /// Families whose regular style is fixed-width, since the diff lines up its columns by
    /// character. Read once, when Settings first opens.
    @ObservationIgnored private(set) lazy var fixedWidthFamilies: [String] = {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName })
        return families.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    init(preferences: DiffPreferences = DiffPreferences()) {
        layout = preferences.layout
        fontFamily = preferences.fontFamily
        fontSize = preferences.fontSize
        defaultOptions = preferences.defaultOptions
    }

    var font: NSFont {
        DiffPreferences.font(family: fontFamily, size: fontSize)
    }

    private func save(_ change: (DiffPreferences) -> Void) {
        change(DiffPreferences())
        NotificationCenter.default.post(name: DiffPreferences.didChange, object: nil)
    }
}
