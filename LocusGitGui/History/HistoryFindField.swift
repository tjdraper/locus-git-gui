import AppKit

/// The Find in History field above the list. Its magnifying glass menu picks what it searches, Down
/// Arrow or Return moves on to the list, and Esc clears it.
final class HistoryFindField: NSObject, NSSearchFieldDelegate {
    let field = NSSearchField()
    private(set) var searchField: HistorySearch.Field = .message
    var onChange: (() -> Void)?
    var moveToList: (() -> Void)?

    /// Items acting on the history, made by it, so they're the same commands as in the Edit menu.
    init(menuItems: [NSMenuItem]) {
        super.init()
        field.sendsSearchStringImmediately = true
        field.delegate = self
        let menu = NSMenu()
        for item in menuItems {
            menu.addItem(item)
        }
        field.searchMenuTemplate = menu
        updatePlaceholder()
    }

    var search: HistorySearch? {
        HistorySearch(text: field.stringValue, field: searchField)
    }

    func setSearchField(_ searchField: HistorySearch.Field) {
        guard searchField != self.searchField else { return }
        self.searchField = searchField
        updatePlaceholder()
        if search != nil {
            onChange?()
        }
    }

    func controlTextDidChange(_: Notification) {
        onChange?()
    }

    func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }
        moveToList?()
        return true
    }

    private func updatePlaceholder() {
        let command: AppCommand = switch searchField {
        case .message: .findByMessage
        case .author: .findByAuthor
        case .changes: .findInChanges
        }
        field.placeholderString = command.title
    }
}
