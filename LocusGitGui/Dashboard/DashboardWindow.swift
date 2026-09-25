import AppKit

/// Sends the list's keys to the dashboard while the search field has focus, since the field would
/// otherwise take them.
final class DashboardWindow: NSWindow {
    enum KeyCommand {
        case moveUp
        case moveDown
        case open
        case close
        case removeFromList
    }

    var onKeyCommand: ((KeyCommand) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isComposingText, let command = Self.keyCommand(for: event) {
            onKeyCommand?(command)
            return
        }
        super.sendEvent(event)
    }

    /// While an input method is composing text, the arrows pick candidates and Return commits.
    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    private static func keyCommand(for event: NSEvent) -> KeyCommand? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, modifiers) {
        case (upArrowKeyCode, []): return .moveUp
        case (downArrowKeyCode, []): return .moveDown
        case (returnKeyCode, []), (enterKeyCode, []): return .open
        case (escapeKeyCode, []): return .close
        case (deleteKeyCode, .command): return .removeFromList
        default: return nil
        }
    }

    private static let returnKeyCode: UInt16 = 36
    private static let deleteKeyCode: UInt16 = 51
    private static let escapeKeyCode: UInt16 = 53
    private static let enterKeyCode: UInt16 = 76
    private static let downArrowKeyCode: UInt16 = 125
    private static let upArrowKeyCode: UInt16 = 126
}
