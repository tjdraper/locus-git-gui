import AppKit

/// Pins the item selected in the sidebar, or unpins it, from View > Pin in Sidebar or the sidebar's
/// context menu, and writes the pins to the repository.
final class SidebarPinWorkflow: NSObject {
    static let actions: Set<Selector> = [#selector(togglePinInSidebar(_:))]

    weak var window: NSWindow?
    private let sidebar: SidebarModel
    private let workTree: URL

    init(sidebar: SidebarModel, workTree: URL) {
        self.sidebar = sidebar
        self.workTree = workTree
        super.init()
        sidebar.onPinsChange = { [weak self] pins in self?.write(pins) }
    }

    static func title(isPinned: Bool) -> String {
        isPinned ? "Unpin from Sidebar" : AppCommand.togglePinInSidebar.title
    }

    @objc func togglePinInSidebar(_: Any?) {
        guard let selection = pinnableSelection else {
            NSSound.beep()
            return
        }
        sidebar.togglePin(selection)
    }

    private var pinnableSelection: SidebarItemID? {
        guard let selection = sidebar.selection, SidebarPins.canPin(selection), sidebar.contents?.contains(selection) == true else {
            return nil
        }
        return selection
    }

    /// Written here rather than off the main actor, since the pins shown have already changed, and
    /// a refresh reading the file before a later write would put them back for a moment.
    private func write(_ pins: SidebarPins) {
        do {
            try pins.write(to: workTree)
        } catch {
            guard let window else { return }
            let alert = NSAlert(error: error)
            alert.messageText = "The pins couldn’t be saved"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }
}

extension SidebarPinWorkflow: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(togglePinInSidebar(_:)) else { return true }
        let selection = pinnableSelection
        menuItem.title = Self.title(isPinned: selection.map(sidebar.pins.contains) ?? false)
        return selection != nil
    }
}
