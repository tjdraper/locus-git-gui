import AppKit
import SwiftUI

/// An AppKit search field, for the clear button, the Esc-to-clear and the look Finder and Xcode
/// give their filters, none of which a SwiftUI text field has. Down Arrow or Return moves on to the
/// list below it.
struct SidebarFilterField: NSViewRepresentable {
    @Binding var text: String
    let focusRequests: Int
    let moveToList: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, focusRequests: focusRequests, moveToList: moveToList)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Filter"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.text = $text
        context.coordinator.moveToList = moveToList
        guard focusRequests != context.coordinator.focusRequests else { return }
        context.coordinator.focusRequests = focusRequests
        // Deferred, since the field may be in a sidebar that's still sliding back into view.
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        /// The last request acted on, so the field only takes focus when asked again.
        var focusRequests: Int
        var moveToList: () -> Void

        init(text: Binding<String>, focusRequests: Int, moveToList: @escaping () -> Void) {
            self.text = text
            self.focusRequests = focusRequests
            self.moveToList = moveToList
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            moveToList()
            return true
        }
    }
}
