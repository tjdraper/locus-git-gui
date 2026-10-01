import AppKit

/// The menu for one file in a diff, from its header's "…" button or a right-click on its changes.
/// Its commands act on that file, rather than on the one the menu bar's commands would pick.
struct ChangedFileMenu {
    /// What whoever shows the diff can do to the file, such as staging it, listed first.
    var actions: [DiffAction] = []
    /// For the lines right-clicked, above everything for the file.
    var lineActions: [DiffAction] = []
    let isInWorkingTree: Bool
    let opensFileWindows: Bool
    /// Nil where files can't be collapsed.
    let isCollapsed: Bool?
    let openInEditor: () -> Void
    let revealInFinder: () -> Void
    let copyAbsolutePath: () -> Void
    let copyPathFromRepositoryRoot: () -> Void
    let openFileWindow: () -> Void
    let toggleCollapsed: () -> Void

    /// `copying` puts Copy first, for a right-click on selected text.
    func make(copying copyTarget: AnyObject? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let copyTarget {
            menu.addItem(AppCommand.copy.makeMenuItem(target: copyTarget))
            menu.addItem(.separator())
        }
        for action in lineActions {
            menu.addItem(item(action))
        }
        if !lineActions.isEmpty {
            menu.addItem(.separator())
        }
        for action in actions {
            menu.addItem(item(action))
        }
        if !actions.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(item(.openInEditor, isEnabled: isInWorkingTree, perform: openInEditor))
        menu.addItem(item(.revealChangedFileInFinder, isEnabled: isInWorkingTree, perform: revealInFinder))
        menu.addItem(item(.copyAbsolutePath, isEnabled: true, perform: copyAbsolutePath))
        menu.addItem(item(.copyPathFromRepositoryRoot, isEnabled: true, perform: copyPathFromRepositoryRoot))
        menu.addItem(item(.openFileInNewWindow, isEnabled: opensFileWindows, perform: openFileWindow))
        if let isCollapsed {
            menu.addItem(.separator())
            menu.addItem(item(isCollapsed ? .expandFile : .collapseFile, isEnabled: true, perform: toggleCollapsed))
        }
        return menu
    }

    /// Shows the command's shortcut, though the shortcut itself reaches the menu bar's command. The
    /// item holds its target, which a menu item doesn't keep alive by itself.
    private func item(_ command: AppCommand, isEnabled: Bool, perform: @escaping () -> Void) -> NSMenuItem {
        let target = ChangedFileMenuTarget(perform: perform)
        let item = command.makeMenuItem(target: target)
        item.action = #selector(ChangedFileMenuTarget.run(_:))
        item.representedObject = target
        item.isEnabled = isEnabled
        return item
    }

    private func item(_ action: DiffAction) -> NSMenuItem {
        let target = ChangedFileMenuTarget(perform: action.perform)
        let item = NSMenuItem(title: action.menuTitle ?? action.title, action: #selector(ChangedFileMenuTarget.run(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        item.isEnabled = action.isEnabled
        item.toolTip = action.toolTip
        item.state = action.isOn == true ? .on : .off
        return item
    }
}

private final class ChangedFileMenuTarget: NSObject {
    private let perform: () -> Void

    init(perform: @escaping () -> Void) {
        self.perform = perform
    }

    @objc func run(_: Any?) {
        perform()
    }
}
