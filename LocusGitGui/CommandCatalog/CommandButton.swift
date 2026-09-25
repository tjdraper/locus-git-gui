import SwiftUI

/// A command in a SwiftUI context menu, with the same title and shortcut it has in the
/// menu bar.
struct CommandButton: View {
    let command: AppCommand
    var count = 1
    let action: () -> Void

    var body: some View {
        if let shortcut = command.shortcut.flatMap(KeyboardShortcut.init) {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    private var button: some View {
        Button(command.title(count: count), action: action)
    }
}

private extension KeyboardShortcut {
    /// Nil for a key SwiftUI has no name for.
    init?(_ shortcut: KeyShortcut) {
        let key: KeyEquivalent
        switch shortcut.key {
        case KeyShortcut.returnKey: key = .return
        case KeyShortcut.deleteKey: key = .delete
        default:
            guard let character = shortcut.key.first, shortcut.key.count == 1 else { return nil }
            key = KeyEquivalent(character)
        }
        var modifiers: EventModifiers = []
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        self.init(key, modifiers: modifiers)
    }
}
