import AppKit

/// The menu bar, built in code because the app has no SwiftUI `App` or storyboard to build it.
/// Every item is a command from `AppCommand`, apart from the submenus.
enum MainMenu {
    /// Items made by the objects they belong to: some are sent to that object alone, and some it
    /// shows only while its window is in front.
    struct OwnedItems {
        let checkForUpdates: NSMenuItem
        let openRecent: NSMenuItem
        let dashboardFile: [NSMenuItem]
        let dashboardView: [NSMenuItem]
        let commandPalette: [NSMenuItem]
        let goTo: [NSMenuItem]
    }

    static func install(appName: String, items owned: OwnedItems) {
        let main = NSMenu()

        let services = submenu(named: "Services", items: [])
        NSApp.servicesMenu = services.submenu

        main.addItem(submenu(named: appName, items: [
            items(.about),
            [owned.checkForUpdates, .separator(), services, .separator()],
            items(.hide, .hideOthers, .showAll),
            [.separator()],
            items(.quit),
        ]))

        main.addItem(submenu(named: "File", items: [
            items(.newTab, .open),
            [owned.openRecent, .separator()],
            items(.showDashboard),
            owned.dashboardFile,
            [.separator()],
            items(.close),
        ]))

        main.addItem(submenu(named: "Edit", items: [
            items(.undo, .redo),
            [.separator()],
            items(.cut, .copy, .paste, .selectAll),
        ]))

        // AppKit adds the tab bar and full screen items, and retitles the sidebar and toolbar items
        // to Show or Hide as they change.
        main.addItem(submenu(named: "View", items: [
            owned.commandPalette,
            [.separator()],
            items(.showSidebar, .filterSidebar, .showToolbar, .customizeToolbar),
            [.separator()],
            owned.goTo,
            [.separator()],
            items(.showGitLog),
            owned.dashboardView,
        ]))

        let windowMenu = submenu(named: "Window", items: [
            items(.minimize, .zoom),
            [.separator()],
            items(.bringAllToFront),
        ])
        main.addItem(windowMenu)

        // Being the help menu is what gives it the search field that finds any menu item.
        let help = submenu(named: "Help", items: [items(.setupChecklist)])
        main.addItem(help)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu.submenu
        NSApp.helpMenu = help.submenu
    }

    private static func items(_ commands: AppCommand...) -> [NSMenuItem] {
        commands.flatMap { $0.makeMenuItems() }
    }

    private static func submenu(named name: String, items groups: [[NSMenuItem]]) -> NSMenuItem {
        let parent = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: name)
        for item in groups.joined() {
            menu.addItem(item)
        }
        parent.submenu = menu
        return parent
    }
}
