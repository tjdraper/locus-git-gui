import AppKit

/// A key equivalent as a menu item holds it: the key, and the modifiers held with it.
nonisolated struct KeyShortcut: Hashable, Sendable {
    /// Lowercase for a letter, with Shift in `modifiers` instead, so the same shortcut is never
    /// written two ways.
    let key: String
    let modifiers: NSEvent.ModifierFlags

    static let returnKey = "\r"
    static let deleteKey = "\u{8}"

    init(_ key: String, _ modifiers: NSEvent.ModifierFlags = .command) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    /// As a menu item holds it, where an uppercase letter means Shift without the mask saying so.
    /// Nil for an item without one.
    init?(menuItem: NSMenuItem) {
        let key = menuItem.keyEquivalent
        guard !key.isEmpty else { return nil }
        var modifiers = menuItem.keyEquivalentModifierMask
        if key.lowercased() != key {
            modifiers.insert(.shift)
        }
        self.init(key.lowercased(), modifiers)
    }

    /// In the order and with the glyphs the menu bar draws them, such as ⌥⌘F.
    var displayText: String {
        var text = ""
        for (modifier, glyph) in Self.modifierGlyphs where modifiers.contains(modifier) {
            text += glyph
        }
        return text + (Self.keyGlyphs[key] ?? key.uppercased())
    }

    /// Written out because `NSEvent.ModifierFlags` isn't `Hashable`.
    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }

    private static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    private static let modifierGlyphs: [(NSEvent.ModifierFlags, String)] = [
        (.control, "⌃"),
        (.option, "⌥"),
        (.shift, "⇧"),
        (.command, "⌘"),
    ]

    private static let keyGlyphs: [String: String] = [
        returnKey: "↩",
        deleteKey: "⌫",
        "\t": "⇥",
        " ": "Space",
    ]
}
