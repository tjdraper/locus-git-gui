import AppKit
import Testing

struct KeyShortcutTests {
    @Test(arguments: [
        (KeyShortcut("f", [.command, .option]), "⌥⌘F"),
        (KeyShortcut("s", [.command, .control]), "⌃⌘S"),
        (KeyShortcut("o", [.command, .shift, .option]), "⌥⇧⌘O"),
        (KeyShortcut(KeyShortcut.returnKey, []), "↩"),
        (KeyShortcut(KeyShortcut.deleteKey), "⌘⌫"),
    ])
    func drawsModifiersInTheMenuBarsOrder(shortcut: KeyShortcut, text: String) {
        // Act
        let displayText = shortcut.displayText

        // Assert
        #expect(displayText == text)
    }

    @Test
    func readsAnUppercaseKeyEquivalentAsShift() throws {
        // Arrange
        let item = NSMenuItem(title: "Show Dashboard", action: nil, keyEquivalent: "O")

        // Act
        let shortcut = try #require(KeyShortcut(menuItem: item))

        // Assert
        #expect(shortcut == KeyShortcut("o", [.command, .shift]))
    }

    @Test
    func anItemWithoutAKeyEquivalentHasNoShortcut() {
        // Arrange
        let item = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")

        // Act
        let shortcut = KeyShortcut(menuItem: item)

        // Assert
        #expect(shortcut == nil)
    }
}
