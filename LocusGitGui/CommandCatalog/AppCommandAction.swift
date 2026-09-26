import AppKit
import Sparkle

/// What each command does, as the action its menu item sends. Most go up the responder chain to
/// whichever window, controller or the app handles them, which also decides whether they're enabled.
extension AppCommand {
    var action: Selector {
        switch self {
        case .about: #selector(AppDelegate.showAboutPanel(_:))
        case .checkForUpdates: #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        case .hide: #selector(NSApplication.hide(_:))
        case .hideOthers: #selector(NSApplication.hideOtherApplications(_:))
        case .showAll: #selector(NSApplication.unhideAllApplications(_:))
        case .quit: #selector(NSApplication.terminate(_:))
        case .newTab: #selector(AppDelegate.newWindowForTab(_:))
        case .open: #selector(AppDelegate.openRepository(_:))
        case .showDashboard: #selector(AppDelegate.showDashboard(_:))
        case .openSelectedRepositories: #selector(DashboardWindowPresenter.openSelection(_:))
        case .removeSelectedRepositories: #selector(DashboardWindowPresenter.removeSelection(_:))
        case .removeAllMissingRepositories: #selector(DashboardWindowPresenter.removeAllMissing(_:))
        case .showRepositoryInFinder: #selector(DashboardWindowPresenter.showSelectionInFinder(_:))
        case .setDisplayName: #selector(DashboardWindowPresenter.setDisplayNameOfSelection(_:))
        case .close: #selector(NSWindow.performClose(_:))
        case .undo: Selector(("undo:"))
        case .redo: Selector(("redo:"))
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .selectAll: #selector(NSText.selectAll(_:))
        case .findInHistory: #selector(HistoryViewController.findInHistory(_:))
        case .findByMessage: #selector(HistoryViewController.findByMessage(_:))
        case .findByAuthor: #selector(HistoryViewController.findByAuthor(_:))
        case .findInChanges: #selector(HistoryViewController.findInChanges(_:))
        case .commandPalette: #selector(CommandPalettePresenter.showCommandPalette(_:))
        case .showSidebar: #selector(NSSplitViewController.toggleSidebar(_:))
        case .filterSidebar: #selector(RepositoryWindowController.filterSidebar(_:))
        case .showToolbar: #selector(NSWindow.toggleToolbarShown(_:))
        case .customizeToolbar: #selector(NSWindow.runToolbarCustomizationPalette(_:))
        case .goToBranch: #selector(CommandPalettePresenter.goToBranch(_:))
        case .goToTag: #selector(CommandPalettePresenter.goToTag(_:))
        case .goToStash: #selector(CommandPalettePresenter.goToStash(_:))
        case .showGitLog: #selector(RepositoryWindowController.showGitLog(_:))
        case .showOnlyMissingRepositories: #selector(DashboardWindowPresenter.toggleShowOnlyMissing(_:))
        case .copyCommitHash: #selector(HistoryViewController.copyCommitHash(_:))
        case .copyCommitSubject: #selector(HistoryViewController.copyCommitSubject(_:))
        case .goToParentCommit: #selector(CommandPalettePresenter.goToParentCommit(_:))
        case .revealCommitInSidebar: #selector(CommandPalettePresenter.revealCommitInSidebar(_:))
        case .showFullMessage: #selector(CommitDetailViewController.toggleFullMessage(_:))
        case .minimize: #selector(NSWindow.performMiniaturize(_:))
        case .zoom: #selector(NSWindow.performZoom(_:))
        case .bringAllToFront: #selector(NSApplication.arrangeInFront(_:))
        case .setupChecklist: #selector(AppDelegate.showSetupChecklist(_:))
        }
    }

    /// The command's menu item, followed by a hidden one for its alternate shortcut when it has one.
    func makeMenuItems(target: AnyObject? = nil) -> [NSMenuItem] {
        let item = makeMenuItem(target: target)
        guard let alternateShortcut else { return [item] }
        let alternate = makeMenuItem(shortcut: alternateShortcut, target: target)
        alternate.isHidden = true
        alternate.allowsKeyEquivalentWhenHidden = true
        return [item, alternate]
    }

    /// `target` is for a command that belongs to one object rather than to the responder chain.
    func makeMenuItem(target: AnyObject? = nil) -> NSMenuItem {
        makeMenuItem(shortcut: shortcut, target: target)
    }

    private func makeMenuItem(shortcut: KeyShortcut?, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.key ?? "")
        item.keyEquivalentModifierMask = shortcut?.modifiers ?? []
        item.identifier = NSUserInterfaceItemIdentifier(rawValue)
        item.target = target
        return item
    }

    /// The command a menu item was made for, if it was made from the catalog.
    init?(menuItem: NSMenuItem) {
        guard let identifier = menuItem.identifier?.rawValue else { return nil }
        self.init(rawValue: identifier)
    }
}
