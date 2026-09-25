import AppKit

/// The menu bar's commands as they stand for the window in front, which is what makes every menu
/// item a palette command without a second list to keep. Read before the palette takes focus, since
/// the menus validate against whatever window has it.
enum MenuBarCommandReader {
    /// Only what's enabled and shown, titled as the menu would title it now, such as Hide Sidebar
    /// rather than Show Sidebar. Submenus, the Services menu and the Window menu's list of windows
    /// are left out.
    static func read(excluding excluded: Set<AppCommand>) -> [CommandPaletteEntry] {
        guard let menuBar = NSApp.mainMenu else { return [] }
        var entries: [CommandPaletteEntry] = []
        var ids: Set<String> = []
        for menuTitle in menuBar.items {
            guard let menu = menuTitle.submenu, menu !== NSApp.servicesMenu else { continue }
            menu.update()
            for item in menu.items where isOffered(item) {
                let command = AppCommand(menuItem: item)
                if let command, excluded.contains(command) {
                    continue
                }
                // An item AppKit added has no command, and is known by its action. Its title is
                // added only for the rare two with the same action, since AppKit retitles some.
                var id = command?.rawValue ?? item.action.map(NSStringFromSelector) ?? item.title
                if ids.contains(id) {
                    id += " " + item.title
                }
                ids.insert(id)
                entries.append(CommandPaletteEntry(
                    item: CommandPaletteItem(
                        id: id,
                        title: item.title,
                        detail: menu.title,
                        shortcut: KeyShortcut(menuItem: item)?.displayText,
                        isListedBeforeTyping: true
                    ),
                    action: .perform { [weak menu, weak item] in
                        guard let menu, let item else { return }
                        perform(item, in: menu)
                    }
                ))
            }
        }
        return entries
    }

    private static func isOffered(_ item: NSMenuItem) -> Bool {
        !item.isSeparatorItem && !item.isHidden && item.isEnabled && item.action != nil && !item.hasSubmenu
            && !item.title.isEmpty && !(item.target is NSWindow)
    }

    /// As if chosen from the menu, once the window it was read for has focus again. Checked again
    /// first, since the palette was open for a while.
    private static func perform(_ item: NSMenuItem, in menu: NSMenu) {
        menu.update()
        let index = menu.index(of: item)
        guard index >= 0, item.isEnabled else { return }
        menu.performActionForItem(at: index)
    }
}
