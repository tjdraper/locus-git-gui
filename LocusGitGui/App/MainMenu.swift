import AppKit

/// The menu bar, built in code because the app has no SwiftUI `App` or storyboard to build it.
enum MainMenu {
    static func install(
        appName: String,
        checkForUpdatesItem: NSMenuItem,
        openRecentItem: NSMenuItem,
        dashboardFileItems: [NSMenuItem],
        dashboardViewItems: [NSMenuItem]
    ) {
        let main = NSMenu()

        let services = submenu(named: "Services", items: [])
        NSApp.servicesMenu = services.submenu

        main.addItem(submenu(named: appName, items: [
            NSMenuItem(title: "About \(appName)", action: #selector(AppDelegate.showAboutPanel(_:)), keyEquivalent: ""),
            checkForUpdatesItem,
            .separator(),
            services,
            .separator(),
            NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            hideOthersItem(),
            NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))

        main.addItem(fileMenu(openRecentItem: openRecentItem, dashboardItems: dashboardFileItems))

        main.addItem(submenu(named: "Edit", items: [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))

        // AppKit adds the tab bar and full screen items.
        main.addItem(submenu(named: "View", items: [
            NSMenuItem(title: "Show Git Log", action: #selector(RepositoryWindowController.showGitLog(_:)), keyEquivalent: ""),
        ] + dashboardViewItems))

        let windowMenu = submenu(named: "Window", items: [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""),
        ])
        main.addItem(windowMenu)

        // Being the help menu is what gives it the search field that finds any menu item.
        let help = submenu(named: "Help", items: [
            NSMenuItem(title: "Setup Checklist", action: #selector(AppDelegate.showSetupChecklist(_:)), keyEquivalent: ""),
        ])
        main.addItem(help)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu.submenu
        NSApp.helpMenu = help.submenu
    }

    private static func fileMenu(openRecentItem: NSMenuItem, dashboardItems: [NSMenuItem]) -> NSMenuItem {
        submenu(named: "File", items: [
            NSMenuItem(title: "Open…", action: #selector(AppDelegate.openRepository(_:)), keyEquivalent: "o"),
            openRecentItem,
            .separator(),
            NSMenuItem(title: "Show Dashboard", action: #selector(AppDelegate.showDashboard(_:)), keyEquivalent: "O"),
            alternateShowDashboardItem(),
        ] + dashboardItems + [
            .separator(),
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ])
    }

    /// A second shortcut for the same command. A menu item has only one, so this one stays hidden.
    private static func alternateShowDashboardItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Show Dashboard", action: #selector(AppDelegate.showDashboard(_:)), keyEquivalent: "O")
        item.keyEquivalentModifierMask = [.command, .shift, .option]
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    private static func hideOthersItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        item.keyEquivalentModifierMask = [.command, .option]
        return item
    }

    private static func submenu(named name: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: name)
        for item in items {
            menu.addItem(item)
        }
        parent.submenu = menu
        return parent
    }
}
