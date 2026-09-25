import AppKit

/// Takes a ⌘-click on the title before the title bar does. The title lets the window be dragged by
/// it, which makes the title bar handle its clicks without the title ever seeing them.
final class RepositoryWindow: NSWindow {
    var onCommandClick: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           onCommandClick?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}
