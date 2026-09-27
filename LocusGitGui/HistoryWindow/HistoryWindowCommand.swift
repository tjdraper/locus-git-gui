import AppKit

/// View > Open History in New Window, for the item selected in the sidebar, named for what it is,
/// such as Open Branch in New Window. The sidebar's context menu opens the item clicked.
final class HistoryWindowCommand: NSObject {
    static let actions: Set<Selector> = [#selector(openHistoryInNewWindow(_:))]

    private let sidebar: SidebarModel
    private let openWindow: (SidebarItemID) -> Void

    init(sidebar: SidebarModel, openWindow: @escaping (SidebarItemID) -> Void) {
        self.sidebar = sidebar
        self.openWindow = openWindow
    }

    @objc func openHistoryInNewWindow(_: Any?) {
        guard let selection = openableSelection else {
            NSSound.beep()
            return
        }
        open(selection)
    }

    func open(_ item: SidebarItemID) {
        openWindow(item)
    }

    private var openableSelection: SidebarItemID? {
        guard let selection = sidebar.selection, sidebar.contents?.contains(selection) == true else { return nil }
        return selection
    }
}

extension HistoryWindowCommand: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(openHistoryInNewWindow(_:)) else { return true }
        guard let selection = openableSelection else {
            menuItem.title = AppCommand.openHistoryInNewWindow.title
            return false
        }
        menuItem.title = "Open \(HistoryWindowTitle(selection, in: sidebar.contents).kind) in New Window"
        return true
    }
}
