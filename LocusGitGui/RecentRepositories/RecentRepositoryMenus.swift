import AppKit
import UniformTypeIdentifiers

/// File > Open Recent and the Dock menu, which list the same repositories as the dashboard.
final class RecentRepositoryMenus: NSObject, NSMenuDelegate {
    /// The system's own default for recent items.
    private static let itemLimit = 10

    let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
    private let recents: RecentRepositoryStore
    private let choose: (Repository) -> Void

    init(recents: RecentRepositoryStore, choose: @escaping (Repository) -> Void) {
        self.recents = recents
        self.choose = choose
        super.init()
        let submenu = NSMenu(title: "Open Recent")
        submenu.delegate = self
        openRecentItem.submenu = submenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items = repositoryItems()
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let clear = NSMenuItem(
            title: "Clear Menu",
            action: recents.repositories.isEmpty ? nil : #selector(clearMenu(_:)),
            keyEquivalent: ""
        )
        clear.target = self
        menu.addItem(clear)
    }

    func dockMenu() -> NSMenu {
        let menu = NSMenu()
        menu.items = repositoryItems()
        return menu
    }

    /// Named against the whole list, so a repository has the same name here as on the dashboard.
    private func repositoryItems() -> [NSMenuItem] {
        let repositories = recents.repositories
        let names = DistinctFolderNames.make(for: repositories.map(\.workTree))
        return zip(repositories, names).prefix(Self.itemLimit).map { repository, name in
            let item = NSMenuItem(title: name, action: #selector(chooseRepository(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = repository
            item.image = Self.folderIcon()
            item.toolTip = (repository.workTree.path as NSString).abbreviatingWithTildeInPath
            return item
        }
    }

    private static func folderIcon() -> NSImage {
        let icon = NSWorkspace.shared.icon(for: .folder)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    @objc private func chooseRepository(_ sender: NSMenuItem) {
        guard let repository = sender.representedObject as? Repository else { return }
        choose(repository)
    }

    /// Clears the dashboard's list too, since it's the same list.
    @objc private func clearMenu(_: Any?) {
        recents.removeAll()
    }
}
