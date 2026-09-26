import AppKit
import Carbon.HIToolbox

/// The history's table, where Return opens the selected commit in its own window, as it opens the
/// selected item in Finder's lists. A table otherwise lets Return pass by.
final class HistoryTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter
        guard isReturn, event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]), let onReturn else {
            super.keyDown(with: event)
            return
        }
        onReturn()
    }
}
