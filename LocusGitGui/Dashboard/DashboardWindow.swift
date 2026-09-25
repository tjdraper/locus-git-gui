import AppKit

/// Sends the list's keys to the dashboard while the search field has focus, since the field would
/// otherwise take them. Command shortcuts belong to the menu bar, which sees them first.
final class DashboardWindow: NSWindow {
    enum KeyCommand {
        case moveUp(extending: Bool)
        case moveDown(extending: Bool)
        case open
        case close
    }

    var onKeyCommand: ((KeyCommand) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isComposingText, let command = Self.keyCommand(for: event) {
            onKeyCommand?(command)
            return
        }
        super.sendEvent(event)
    }

    /// The search field would share the window's undo stack and record its typing there after a
    /// removal made mid-search, so Undo took back the typing instead of the removal. Undo here
    /// only puts back repositories removed from the list.
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        let editor = super.fieldEditor(createFlag, for: object)
        (editor as? NSTextView)?.allowsUndo = false
        return editor
    }

    /// While an input method is composing text, the arrows pick candidates and Return commits.
    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    private static func keyCommand(for event: NSEvent) -> KeyCommand? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, modifiers) {
        case (upArrowKeyCode, []), (upArrowKeyCode, .shift): return .moveUp(extending: modifiers == .shift)
        case (downArrowKeyCode, []), (downArrowKeyCode, .shift): return .moveDown(extending: modifiers == .shift)
        case (returnKeyCode, []), (enterKeyCode, []): return .open
        case (escapeKeyCode, []): return .close
        default: return nil
        }
    }

    private static let returnKeyCode: UInt16 = 36
    private static let escapeKeyCode: UInt16 = 53
    private static let enterKeyCode: UInt16 = 76
    private static let downArrowKeyCode: UInt16 = 125
    private static let upArrowKeyCode: UInt16 = 126
}
