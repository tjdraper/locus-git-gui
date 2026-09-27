import AppKit

/// Asks before a command that loses something. Return confirms and Escape cancels. The button isn't
/// marked destructive, since macOS then keeps Return off it.
enum Confirmation {
    static func ask(_ message: String, informativeText: String, confirmTitle: String, on window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return await AlertPresentation.run(alert, on: window) == .alertFirstButtonReturn
    }
}
