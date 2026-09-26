import AppKit

/// Asks before changes are discarded, and says how to get them back: the file as it was goes to the
/// Trash first, where Put Back returns it to its place.
enum DiscardConfirmation {
    enum Scope {
        case file
        case hunk
        case lines
    }

    static func ask(discarding scope: Scope, of file: DiffFile, on window: NSWindow, then discard: @escaping () -> Void) {
        let alert = NSAlert()
        let name = (file.changed.path as NSString).lastPathComponent
        let isUntracked = WorkingAreaGroup(file) == .untracked
        switch (scope, isUntracked) {
        case (.file, true):
            alert.messageText = "Move “\(name)” to the Trash?"
            alert.informativeText = "Git doesn’t track this file, so the copy in the Trash is the only one."
            alert.addButton(withTitle: "Move to Trash")
        case (.file, false):
            alert.messageText = "Discard the unstaged changes to “\(name)”?"
            alert.informativeText = "The file goes back to how it’s staged, or how it was last committed. "
                + "The file as it is now goes to the Trash first, so it can be put back."
            alert.addButton(withTitle: "Discard Changes")
        case (.hunk, _), (.lines, _):
            alert.messageText = scope == .hunk ? "Discard this change to “\(name)”?" : "Discard the selected lines of “\(name)”?"
            alert.informativeText = "The file as it is now goes to the Trash first, so it can be put back."
            alert.addButton(withTitle: scope == .hunk ? "Discard Change" : "Discard Lines")
        }
        present(alert, on: window, then: discard)
    }

    /// Return discards and Escape cancels. The button isn't marked destructive, since macOS then
    /// keeps Return off it whatever its key equivalent says, and Return only beeped.
    private static func present(_ alert: NSAlert, on window: NSWindow, then discard: @escaping () -> Void) {
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            discard()
        }
    }

    /// When the Trash can't take the file, such as on some network volumes.
    static func askWithoutTrash(for file: DiffFile, because error: any Error, on window: NSWindow, then discard: @escaping () -> Void) {
        let alert = NSAlert()
        let name = (file.changed.path as NSString).lastPathComponent
        alert.messageText = "“\(name)” can’t be moved to the Trash."
        alert.informativeText = "\(error.localizedDescription) Discard the changes anyway? They can’t be recovered."
        alert.addButton(withTitle: "Discard Anyway")
        present(alert, on: window, then: discard)
    }
}
