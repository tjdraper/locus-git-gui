import AppKit
import Carbon.HIToolbox

/// Takes a ⌘-click on the title before the title bar does. The title lets the window be dragged by
/// it, which makes the title bar handle its clicks without the title ever seeing them.
final class RepositoryWindow: NSWindow {
    var onCommandClick: ((NSEvent) -> Bool)?
    /// Given whether Shift was held. True when it moved focus.
    var onTab: ((_ backward: Bool) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           onCommandClick?(event) == true {
            return
        }
        if event.type == .keyDown, Int(event.keyCode) == kVK_Tab,
           event.modifierFlags.isDisjoint(with: [.command, .option, .control]),
           onTab?(event.modifierFlags.contains(.shift)) == true {
            return
        }
        let editing = event.type == .leftMouseDown || event.type == .rightMouseDown ? editingField : nil
        super.sendEvent(event)
        guard let editing, editingField === editing,
              !editing.bounds.contains(editing.convert(event.locationInWindow, from: nil))
        else { return }
        // AppKit leaves a field editing when the click lands on something that doesn't take focus
        // itself, such as an empty column or the toolbar. A SwiftUI list doesn't take focus from a
        // field either, and draws the row just clicked as if the window were in the background.
        makeFirstResponder(focusableView(at: event.locationInWindow))
    }

    private var editingField: NSControl? {
        guard let editor = firstResponder as? NSTextView, editor.isFieldEditor else { return nil }
        return editor.delegate as? NSControl
    }

    /// From the frame view, which holds the toolbar as well as the content.
    private func focusableView(at point: NSPoint) -> NSView? {
        var view = contentView?.superview?.hitTest(point)
        while let candidate = view, !candidate.acceptsFirstResponder {
            view = candidate.superview
        }
        return view
    }
}
