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
        case .cloneRepository: #selector(AppDelegate.cloneRepository(_:))
        case .createRepository: #selector(AppDelegate.createRepository(_:))
        case .showDashboard: #selector(AppDelegate.showDashboard(_:))
        case .openSelectedRepositories: #selector(DashboardWindowPresenter.openSelection(_:))
        case .removeSelectedRepositories: #selector(DashboardWindowPresenter.removeSelection(_:))
        case .removeAllMissingRepositories: #selector(DashboardWindowPresenter.removeAllMissing(_:))
        case .showRepositoryInFinder: #selector(DashboardWindowPresenter.showSelectionInFinder(_:))
        case .setDisplayName: #selector(DashboardWindowPresenter.setDisplayNameOfSelection(_:))
        case .openInEditor: #selector(DiffViewController.openInEditor(_:))
        case .revealChangedFileInFinder: #selector(DiffViewController.revealChangedFileInFinder(_:))
        case .copyAbsolutePath: #selector(DiffViewController.copyAbsolutePath(_:))
        case .copyPathFromRepositoryRoot: #selector(DiffViewController.copyPathFromRepositoryRoot(_:))
        case .openFileInNewWindow: #selector(DiffViewController.openFileInNewWindow(_:))
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
        case .togglePinInSidebar: #selector(SidebarPinWorkflow.togglePinInSidebar(_:))
        case .openHistoryInNewWindow: #selector(HistoryWindowCommand.openHistoryInNewWindow(_:))
        case .showToolbar: #selector(NSWindow.toggleToolbarShown(_:))
        case .customizeToolbar: #selector(NSWindow.runToolbarCustomizationPalette(_:))
        case .goToUncommittedChanges: #selector(RepositoryWindowController.goToUncommittedChanges(_:))
        case .openUncommittedChangesWindow: #selector(RepositoryWindowController.openUncommittedChangesWindow(_:))
        case .goToBranch: #selector(CommandPalettePresenter.goToBranch(_:))
        case .goToTag: #selector(CommandPalettePresenter.goToTag(_:))
        case .goToStash: #selector(CommandPalettePresenter.goToStash(_:))
        case .showAllChanges: #selector(WorkingAreaViewController.showAllChanges(_:))
        case .showStagedChanges: #selector(WorkingAreaViewController.showStagedChanges(_:))
        case .showUnstagedChanges: #selector(WorkingAreaViewController.showUnstagedChanges(_:))
        case .collapseFile: #selector(DiffViewController.collapseFile(_:))
        case .expandFile: #selector(DiffViewController.expandFile(_:))
        case .collapseAllFiles: #selector(DiffViewController.collapseAllFiles(_:))
        case .expandAllFiles: #selector(DiffViewController.expandAllFiles(_:))
        case .goToNextFile: #selector(DiffViewController.goToNextFile(_:))
        case .goToPreviousFile: #selector(DiffViewController.goToPreviousFile(_:))
        case .ignoreWhitespace: #selector(DiffViewController.toggleIgnoreWhitespace(_:))
        case .showMoreContext: #selector(DiffViewController.showMoreContext(_:))
        case .showLessContext: #selector(DiffViewController.showLessContext(_:))
        case .showMessageAsMarkdown: #selector(MessageFormatStore.toggleMessageMarkdown(_:))
        case .showActivity: #selector(RepositoryWindowController.showActivity(_:))
        case .showOnlyMissingRepositories: #selector(DashboardWindowPresenter.toggleShowOnlyMissing(_:))
        case .checkOutBranch: #selector(CommandPalettePresenter.checkOutBranch(_:))
        case .newBranch: #selector(OperationMenuCommands.newBranch(_:))
        case .renameBranch: #selector(CommandPalettePresenter.renameBranch(_:))
        case .deleteBranch: #selector(CommandPalettePresenter.deleteBranch(_:))
        case .setUpstream: #selector(CommandPalettePresenter.setUpstream(_:))
        case .unsetUpstream: #selector(OperationMenuCommands.unsetUpstream(_:))
        case .mergeIntoCurrentBranch: #selector(CommandPalettePresenter.mergeIntoCurrentBranch(_:))
        case .rebaseCurrentBranch: #selector(CommandPalettePresenter.rebaseCurrentBranch(_:))
        case .newTag: #selector(OperationMenuCommands.newTag(_:))
        case .deleteTag: #selector(CommandPalettePresenter.deleteTag(_:))
        case .continueOperation: #selector(OperationMenuCommands.continueOperation(_:))
        case .skipCommit: #selector(OperationMenuCommands.skipCommit(_:))
        case .abortOperation: #selector(OperationMenuCommands.abortOperation(_:))
        case .commitChanges: #selector(WorkingAreaViewController.commitChanges(_:))
        case .amendLastCommit: #selector(WorkingAreaViewController.toggleAmend(_:))
        case .toggleFileStaging: #selector(WorkingAreaViewController.toggleFileStaging(_:))
        case .toggleHunkStaging: #selector(WorkingAreaViewController.toggleHunkStaging(_:))
        case .discardFile: #selector(WorkingAreaViewController.discardFile(_:))
        case .discardHunk: #selector(WorkingAreaViewController.discardHunk(_:))
        case .stageAll: #selector(WorkingAreaViewController.stageAll(_:))
        case .unstageAll: #selector(WorkingAreaViewController.unstageAll(_:))
        case .openCommitInNewWindow: #selector(HistoryViewController.openCommitInNewWindow(_:))
        case .copyCommitHash: #selector(HistoryViewController.copyCommitHash(_:))
        case .copyCommitSubject: #selector(HistoryViewController.copyCommitSubject(_:))
        case .goToParentCommit: #selector(CommandPalettePresenter.goToParentCommit(_:))
        case .revealCommitInSidebar: #selector(CommandPalettePresenter.revealCommitInSidebar(_:))
        case .showFullMessage: #selector(CommitDetailViewController.toggleFullMessage(_:))
        case .checkOutCommit: #selector(OperationMenuCommands.checkOutCommit(_:))
        case .newBranchFromCommit: #selector(OperationMenuCommands.newBranchFromCommit(_:))
        case .newTagOnCommit: #selector(OperationMenuCommands.newTagOnCommit(_:))
        case .cherryPickCommit: #selector(OperationMenuCommands.cherryPickCommit(_:))
        case .revertCommit: #selector(OperationMenuCommands.revertCommit(_:))
        case .softResetToCommit: #selector(OperationMenuCommands.softResetToCommit(_:))
        case .mixedResetToCommit: #selector(OperationMenuCommands.mixedResetToCommit(_:))
        case .hardResetToCommit: #selector(OperationMenuCommands.hardResetToCommit(_:))
        case .rewordCommit: #selector(OperationMenuCommands.rewordCommit(_:))
        case .editCommit: #selector(OperationMenuCommands.editCommit(_:))
        case .stashChanges: #selector(OperationMenuCommands.stashChanges(_:))
        case .stashIncludingUntracked: #selector(OperationMenuCommands.stashIncludingUntracked(_:))
        case .applyStash: #selector(CommandPalettePresenter.applyStash(_:))
        case .popStash: #selector(CommandPalettePresenter.popStash(_:))
        case .dropStash: #selector(CommandPalettePresenter.dropStash(_:))
        case .fetch: #selector(RemoteSyncWorkflow.fetch(_:))
        case .fetchWithoutOptions: #selector(RemoteSyncWorkflow.fetchWithoutOptions(_:))
        case .fetchAndPrune: #selector(RemoteSyncWorkflow.fetchAndPrune(_:))
        case .fetchWithTags: #selector(RemoteSyncWorkflow.fetchWithTags(_:))
        case .prunesWhenFetching: #selector(FetchPreferences.togglePruneWhenFetching(_:))
        case .fetchesTagsWhenFetching: #selector(FetchPreferences.toggleTagsWhenFetching(_:))
        case .pull: #selector(RemoteSyncWorkflow.pull(_:))
        case .push: #selector(RemoteSyncWorkflow.push(_:))
        case .forcePush: #selector(RemoteSyncWorkflow.forcePush(_:))
        case .fetchAutomatically: #selector(FetchPreferences.toggleAutomaticFetch(_:))
        case .addRemote: #selector(RemoteEditingWorkflow.addRemote(_:))
        case .fetchFromRemote: #selector(CommandPalettePresenter.fetchFromRemote(_:))
        case .editRemote: #selector(CommandPalettePresenter.editRemote(_:))
        case .removeRemote: #selector(CommandPalettePresenter.removeRemote(_:))
        case .pushTag: #selector(CommandPalettePresenter.pushTag(_:))
        case .deleteRemoteTag: #selector(CommandPalettePresenter.deleteRemoteTag(_:))
        case .deleteRemoteBranch: #selector(CommandPalettePresenter.deleteRemoteBranch(_:))
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
