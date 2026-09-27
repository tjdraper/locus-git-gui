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
        let commitGoTo: [NSMenuItem]
        let fetchPreferences: [NSMenuItem]
        let fetchVariants: [NSMenuItem]
        let remoteChoices: [NSMenuItem]
        let tagChoices: [NSMenuItem]
        /// Branch, tag and stash commands that ask which one in the palette.
        let operationChoices: [AppCommand: NSMenuItem]

        func choices(_ commands: AppCommand...) -> [NSMenuItem] {
            commands.compactMap { operationChoices[$0] }
        }
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
            items(.newTab, .open, .cloneRepository, .createRepository),
            [owned.openRecent, .separator()],
            items(.showDashboard),
            owned.dashboardFile,
            [.separator()],
            items(.openInEditor, .revealChangedFileInFinder, .copyAbsolutePath, .copyPathFromRepositoryRoot, .openFileInNewWindow),
            [.separator()],
            items(.close),
        ]))

        main.addItem(submenu(named: "Edit", items: [
            items(.undo, .redo),
            [.separator()],
            items(.cut, .copy, .paste, .selectAll),
            [.separator()],
            items(.findInHistory, .findByMessage, .findByAuthor, .findInChanges),
        ]))

        main.addItem(viewMenu(owned))
        main.addItem(branchMenu(owned))
        main.addItem(commitMenu(owned))
        main.addItem(stashMenu(owned))
        main.addItem(remoteMenu(owned))

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

    /// AppKit adds the tab bar and full screen items, and retitles the sidebar and toolbar items to
    /// Show or Hide as they change.
    private static func viewMenu(_ owned: OwnedItems) -> NSMenuItem {
        submenu(named: "View", items: [
            owned.commandPalette,
            [.separator()],
            items(.showSidebar, .filterSidebar, .togglePinInSidebar, .openHistoryInNewWindow, .showToolbar, .customizeToolbar),
            [.separator()],
            items(.goToUncommittedChanges, .openUncommittedChangesWindow),
            owned.goTo,
            [.separator()],
            items(.showAllChanges, .showStagedChanges, .showUnstagedChanges),
            [.separator()],
            items(.collapseFile, .expandFile, .collapseAllFiles, .expandAllFiles, .goToNextFile, .goToPreviousFile),
            [.separator()],
            items(.ignoreWhitespace, .showMoreContext, .showLessContext),
            [.separator()],
            items(.showActivity),
            owned.dashboardView,
        ])
    }

    /// Merge and rebase act on the checked-out branch, so they're here rather than with the
    /// commit's own commands.
    private static func branchMenu(_ owned: OwnedItems) -> NSMenuItem {
        submenu(named: "Branch", items: [
            owned.choices(.checkOutBranch),
            items(.newBranch),
            owned.choices(.renameBranch, .deleteBranch),
            [.separator()],
            owned.choices(.setUpstream),
            items(.unsetUpstream),
            [.separator()],
            owned.choices(.mergeIntoCurrentBranch, .rebaseCurrentBranch),
            [.separator()],
            items(.newTag),
            owned.choices(.deleteTag),
        ])
    }

    /// Continue, Skip and Abort come first while an operation has stopped partway, since finishing
    /// it is what the window is waiting for.
    private static func commitMenu(_ owned: OwnedItems) -> NSMenuItem {
        submenu(named: "Commit", items: [
            items(.continueOperation, .skipCommit, .abortOperation),
            [.separator()],
            items(.commitChanges, .amendLastCommit),
            [.separator()],
            items(.toggleFileStaging, .toggleHunkStaging, .discardFile, .discardHunk),
            [.separator()],
            items(.stageAll, .unstageAll),
            [.separator()],
            items(.openCommitInNewWindow),
            [.separator()],
            items(.copyCommitHash, .copyCommitSubject),
            [.separator()],
            owned.commitGoTo,
            [.separator()],
            items(.showFullMessage),
            [.separator()],
            items(.checkOutCommit, .newBranchFromCommit, .newTagOnCommit),
            [.separator()],
            items(.cherryPickCommit, .revertCommit),
            [.separator()],
            items(.softResetToCommit, .mixedResetToCommit, .hardResetToCommit),
            [.separator()],
            items(.rewordCommit, .editCommit),
        ])
    }

    private static func stashMenu(_ owned: OwnedItems) -> NSMenuItem {
        submenu(named: "Stash", items: [
            items(.stashChanges, .stashIncludingUntracked),
            [.separator()],
            owned.choices(.applyStash, .popStash, .dropStash),
        ])
    }

    private static func remoteMenu(_ owned: OwnedItems) -> NSMenuItem {
        submenu(named: "Remote", items: [
            items(.fetch),
            owned.fetchVariants,
            items(.pull, .push, .forcePush),
            [.separator()],
            owned.fetchPreferences,
            [.separator()],
            items(.addRemote),
            owned.remoteChoices,
            [.separator()],
            owned.choices(.deleteRemoteBranch),
            owned.tagChoices,
        ])
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
