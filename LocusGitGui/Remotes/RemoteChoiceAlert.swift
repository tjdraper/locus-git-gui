import AppKit

/// Asks which remote to use when nothing configured says, with the remotes in a pop-up menu.
enum RemoteChoiceAlert {
    static func ask(
        _ message: String,
        informativeText: String,
        remotes: [String],
        confirmTitle: String,
        on window: NSWindow?
    ) async -> String? {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        let menu = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        menu.addItems(withTitles: remotes)
        alert.accessoryView = menu
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = menu
        guard await AlertPresentation.run(alert, on: window) == .alertFirstButtonReturn else {
            return nil
        }
        return menu.titleOfSelectedItem
    }
}
