import AppKit

/// The menu for a commit Control-clicked in the history, which acts on that commit whether or not
/// it's the one selected.
final class HistoryContextMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let commitForMenu: () -> Commit?
    private let labels: (String) -> [CommitRefLabel]
    private let parentTitle: (String) -> String
    private let goToCommit: (String) -> Void
    private let reveal: (SidebarItemID) -> Void

    init(
        commitForMenu: @escaping () -> Commit?,
        labels: @escaping (String) -> [CommitRefLabel],
        parentTitle: @escaping (String) -> String,
        goToCommit: @escaping (String) -> Void,
        reveal: @escaping (SidebarItemID) -> Void
    ) {
        self.commitForMenu = commitForMenu
        self.labels = labels
        self.parentTitle = parentTitle
        self.goToCommit = goToCommit
        self.reveal = reveal
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let commit = commitForMenu() else { return }
        menu.addItem(item(.copyCommitHash, #selector(copyText(_:)), commit.hash))
        menu.addItem(item(.copyCommitSubject, #selector(copyText(_:)), commit.subject))
        menu.addItem(.separator())
        menu.addItem(choiceItem(
            .goToParentCommit,
            #selector(goToParent(_:)),
            choices: commit.parents.map { (title: parentTitle($0), value: $0) }
        ))
        let revealable = labels(commit.hash).compactMap { label in label.sidebarItem.map { (title: label.name, value: $0) } }
        menu.addItem(choiceItem(.revealCommitInSidebar, #selector(revealItem(_:)), choices: revealable))
    }

    private func item(_ command: AppCommand, _ action: Selector, _ value: Any?) -> NSMenuItem {
        let item = command.makeMenuItem(target: self)
        item.action = action
        item.representedObject = value
        return item
    }

    /// Acts straight away with one choice, lists them in a submenu with several, and is disabled
    /// with none.
    private func choiceItem(_ command: AppCommand, _ action: Selector, choices: [(title: String, value: Any)]) -> NSMenuItem {
        guard choices.count > 1 else {
            return item(command, action, choices.first?.value)
        }
        let item = NSMenuItem(title: command.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for choice in choices {
            let choiceItem = NSMenuItem(title: choice.title, action: action, keyEquivalent: "")
            choiceItem.target = self
            choiceItem.representedObject = choice.value
            submenu.addItem(choiceItem)
        }
        item.submenu = submenu
        return item
    }

    @objc private func copyText(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func goToParent(_ sender: NSMenuItem) {
        guard let hash = sender.representedObject as? String else { return }
        goToCommit(hash)
    }

    @objc private func revealItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? SidebarItemID else { return }
        reveal(id)
    }
}

extension HistoryContextMenu: NSMenuItemValidation {
    /// An item without a value is a command with nothing to act on, such as Go to Parent on a root
    /// commit.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.hasSubmenu || menuItem.representedObject != nil
    }
}
