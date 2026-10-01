import AppKit

/// Every command the app offers. The menu bar, context menus and the command palette all take a
/// command's title and shortcut from here, so they can't disagree about what it's called or
/// which keys reach it. Its action is in `AppCommandAction`, which reaches into the rest of the app.
nonisolated enum AppCommand: String, CaseIterable, Sendable {
    case about
    case installWaitingUpdate
    case checkForUpdates
    case purchase
    case settings
    case hide
    case hideOthers
    case showAll
    case quit

    case newTab
    case open
    case cloneRepository
    case createRepository
    case showDashboard
    case openSelectedRepositories
    case removeSelectedRepositories
    case removeAllMissingRepositories
    case showRepositoryInFinder
    case setDisplayName
    case openInEditor
    case revealChangedFileInFinder
    case copyAbsolutePath
    case copyPathFromRepositoryRoot
    case openFileInNewWindow
    case close
    case saveConflictResolution

    case undo
    case redo
    case cut
    case copy
    case paste
    case selectAll
    case findInHistory
    case findByMessage
    case findByAuthor
    case findInChanges

    case commandPalette
    case showSidebar
    case filterSidebar
    case togglePinInSidebar
    case openHistoryInNewWindow
    case showToolbar
    case customizeToolbar
    case goToUncommittedChanges
    case openUncommittedChangesWindow
    case showConflicts
    case goToBranch
    case goToTag
    case goToStash
    case showAllChanges
    case showStagedChanges
    case showUnstagedChanges
    case collapseFile
    case expandFile
    case collapseAllFiles
    case expandAllFiles
    case goToNextFile
    case goToPreviousFile
    case ignoreWhitespace
    case showMoreContext
    case showLessContext
    case showMessageAsMarkdown
    case showConflictBase
    case showActivity
    case showNotices
    case showOnlyMissingRepositories

    case checkOutBranch
    case newBranch
    case renameBranch
    case deleteBranch
    case setUpstream
    case unsetUpstream
    case mergeIntoCurrentBranch
    case rebaseCurrentBranch
    case newTag
    case deleteTag

    case continueOperation
    case skipCommit
    case abortOperation
    case goToPreviousConflict
    case goToNextConflict
    case takeOurs
    case takeTheirs
    case takeBoth
    case markConflictResolved
    case commitChanges
    case amendLastCommit
    case toggleFileStaging
    case toggleHunkStaging
    case discardFile
    case discardHunk
    case stageAll
    case unstageAll
    case openCommitInNewWindow
    case copyCommitHash
    case copyCommitSubject
    case goToParentCommit
    case revealCommitInSidebar
    case showFullMessage
    case checkOutCommit
    case newBranchFromCommit
    case newTagOnCommit
    case cherryPickCommit
    case revertCommit
    case softResetToCommit
    case mixedResetToCommit
    case hardResetToCommit
    case rewordCommit
    case editCommit

    case stashChanges
    case stashIncludingUntracked
    case applyStash
    case popStash
    case dropStash

    case fetch
    case fetchWithoutOptions
    case fetchAndPrune
    case fetchWithTags
    case pull
    case push
    case forcePush
    case prunesWhenFetching
    case fetchesTagsWhenFetching
    case fetchAutomatically
    case addRemote
    case fetchFromRemote
    case editRemote
    case removeRemote
    case pushTag
    case deleteRemoteTag
    case deleteRemoteBranch

    case newReview
    case showReviews
    case markFileReviewed
    case goToNextUnreviewedFile
    case showChangesSinceReviewed
    case addReviewComment
    case copyReviewComments
    case renameReview
    case deleteReview

    case minimize
    case zoom
    case bringAllToFront

    case setupChecklist
}

/// Titles and shortcuts, which the menus and the palette show.
nonisolated extension AppCommand {
    var title: String {
        switch self {
        case .about: "About Locus Git Gui"
        case .installWaitingUpdate: "Install Update…"
        case .checkForUpdates: "Check for Updates…"
        case .purchase: "Purchase…"
        case .settings: "Settings…"
        case .hide: "Hide Locus Git Gui"
        case .hideOthers: "Hide Others"
        case .showAll: "Show All"
        case .quit: "Quit Locus Git Gui"
        case .newTab: "New Tab"
        case .open: "Open…"
        case .cloneRepository: "Clone Repository…"
        case .createRepository: "Create Repository…"
        case .showDashboard: "Show Dashboard"
        case .openSelectedRepositories: title(count: 1)
        case .removeSelectedRepositories: title(count: 1)
        case .removeAllMissingRepositories: "Remove All Missing Repositories"
        case .showRepositoryInFinder: "Show in Finder"
        case .setDisplayName: "Set Display Name…"
        case .openInEditor: "Open in Editor"
        case .revealChangedFileInFinder: "Reveal in Finder"
        case .copyAbsolutePath: "Copy Absolute Path"
        case .copyPathFromRepositoryRoot: "Copy Path from Repository Root"
        case .openFileInNewWindow: "Open File in New Window"
        case .close: "Close"
        case .saveConflictResolution: "Save"
        case .undo: "Undo"
        case .redo: "Redo"
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        case .selectAll: "Select All"
        case .findInHistory: "Find in History"
        case .findByMessage: "Find by Message or Hash"
        case .findByAuthor: "Find by Author"
        case .findInChanges: "Find in Changes"
        case .commandPalette: "Command Palette…"
        case .showSidebar: "Show Sidebar"
        case .filterSidebar: "Filter Sidebar"
        case .togglePinInSidebar: "Pin in Sidebar"
        case .openHistoryInNewWindow: "Open History in New Window"
        case .showToolbar: "Show Toolbar"
        case .customizeToolbar: "Customize Toolbar…"
        case .goToUncommittedChanges: "Go to Uncommitted Changes"
        case .openUncommittedChangesWindow: "Open Uncommitted Changes in New Window"
        case .showConflicts: "Show Conflicts"
        case .goToBranch: "Go to Branch…"
        case .goToTag: "Go to Tag…"
        case .goToStash: "Go to Stash…"
        case .showAllChanges: "Show All Changes"
        case .showStagedChanges: "Show Staged Changes"
        case .showUnstagedChanges: "Show Unstaged Changes"
        case .collapseFile: "Collapse File"
        case .expandFile: "Expand File"
        case .collapseAllFiles: "Collapse All Files"
        case .expandAllFiles: "Expand All Files"
        case .goToNextFile: "Next File"
        case .goToPreviousFile: "Previous File"
        case .ignoreWhitespace: "Ignore Whitespace"
        case .showMoreContext: "More Context Lines"
        case .showLessContext: "Fewer Context Lines"
        case .showMessageAsMarkdown: "Show Message as Markdown"
        case .showConflictBase: "Show Base"
        case .showActivity: "Show Activity"
        case .showNotices: "Show Notices"
        case .showOnlyMissingRepositories: "Show Only Missing Repositories"
        case .checkOutBranch: "Check Out Branch…"
        case .newBranch: "New Branch…"
        case .renameBranch: "Rename Branch…"
        case .deleteBranch: "Delete Branch…"
        case .setUpstream: "Set Upstream…"
        case .unsetUpstream: "Unset Upstream"
        case .mergeIntoCurrentBranch: "Merge into Current Branch…"
        case .rebaseCurrentBranch: "Rebase Current Branch onto…"
        case .newTag: "New Tag…"
        case .deleteTag: "Delete Tag…"
        case .continueOperation: "Continue"
        case .skipCommit: "Skip Commit"
        case .abortOperation: "Abort…"
        case .goToPreviousConflict: "Previous Conflict"
        case .goToNextConflict: "Next Conflict"
        case .takeOurs: "Take Ours"
        case .takeTheirs: "Take Theirs"
        case .takeBoth: "Take Both"
        case .markConflictResolved: "Mark as Resolved"
        case .commitChanges: "Commit"
        case .amendLastCommit: "Amend Last Commit"
        case .toggleFileStaging: "Stage File"
        case .toggleHunkStaging: "Stage Hunk"
        case .discardFile: "Discard Changes…"
        case .discardHunk: "Discard Hunk…"
        case .stageAll: "Stage All"
        case .unstageAll: "Unstage All"
        case .openCommitInNewWindow: "Open in New Window"
        case .copyCommitHash: "Copy Hash"
        case .copyCommitSubject: "Copy Subject"
        case .goToParentCommit: "Go to Parent"
        case .revealCommitInSidebar: "Reveal in Sidebar"
        case .showFullMessage: "Show Full Message"
        case .checkOutCommit: "Check Out Commit"
        case .newBranchFromCommit: "New Branch from Commit…"
        case .newTagOnCommit: "New Tag on Commit…"
        case .cherryPickCommit: "Cherry-Pick Commit"
        case .revertCommit: "Revert Commit"
        case .softResetToCommit: "Soft Reset to Commit"
        case .mixedResetToCommit: "Mixed Reset to Commit"
        case .hardResetToCommit: "Hard Reset to Commit…"
        case .rewordCommit: "Reword Commit…"
        case .editCommit: "Edit Commit…"
        case .stashChanges: "Stash Changes…"
        case .stashIncludingUntracked: "Stash Including Untracked Files…"
        case .applyStash: "Apply Stash…"
        case .popStash: "Pop Stash…"
        case .dropStash: "Drop Stash…"
        case .fetch: "Fetch"
        case .fetchWithoutOptions: "Fetch without Pruning or Tags"
        case .fetchAndPrune: "Fetch and Prune"
        case .fetchWithTags: "Fetch with Tags"
        case .prunesWhenFetching: "Prune When Fetching"
        case .fetchesTagsWhenFetching: "Fetch Tags When Fetching"
        case .pull: "Pull"
        case .push: "Push"
        case .forcePush: "Force Push…"
        case .fetchAutomatically: "Fetch Automatically"
        case .addRemote: "Add Remote…"
        case .fetchFromRemote: "Fetch from Remote…"
        case .editRemote: "Edit Remote…"
        case .removeRemote: "Remove Remote…"
        case .pushTag: "Push Tag…"
        case .deleteRemoteTag: "Delete Tag from Remote…"
        case .deleteRemoteBranch: "Delete Branch from Remote…"
        case .newReview: "New Review"
        case .showReviews: "Show Reviews"
        case .markFileReviewed: "Mark as Reviewed"
        case .goToNextUnreviewedFile: "Next Unreviewed File"
        case .showChangesSinceReviewed: "Show Only Changes Since Reviewed"
        case .addReviewComment: "Add Comment"
        case .copyReviewComments: "Copy Comments as Markdown"
        case .renameReview: "Rename Review…"
        case .deleteReview: "Delete Review…"
        case .minimize: "Minimize"
        case .zoom: "Zoom"
        case .bringAllToFront: "Bring All to Front"
        case .setupChecklist: "Setup Checklist"
        }
    }

    var shortcut: KeyShortcut? {
        switch self {
        case .settings: KeyShortcut(",")
        case .hide: KeyShortcut("h")
        case .hideOthers: KeyShortcut("h", [.command, .option])
        case .quit: KeyShortcut("q")
        case .newTab: KeyShortcut("t")
        case .open: KeyShortcut("o")
        case .showDashboard: KeyShortcut("o", [.command, .shift])
        case .openSelectedRepositories: KeyShortcut(KeyShortcut.returnKey, [])
        case .removeSelectedRepositories: KeyShortcut(KeyShortcut.deleteKey)
        case .removeAllMissingRepositories: KeyShortcut(KeyShortcut.deleteKey, [.command, .option])
        // ⌘↩ is Commit, and AppKit shows a shortcut on only one item. ⌘R is Finder's Show in
        // Enclosing Folder.
        case .showRepositoryInFinder: KeyShortcut("r")
        case .openInEditor: KeyShortcut("e", [.command, .option])
        case .revealChangedFileInFinder: KeyShortcut("r", [.command, .option])
        case .copyAbsolutePath: KeyShortcut("c", [.command, .option])
        case .copyPathFromRepositoryRoot: KeyShortcut("c", [.command, .option, .shift])
        case .close: KeyShortcut("w")
        case .saveConflictResolution: KeyShortcut("s")
        case .undo: KeyShortcut("z")
        case .redo: KeyShortcut("z", [.command, .shift])
        case .cut: KeyShortcut("x")
        case .copy: KeyShortcut("c")
        case .paste: KeyShortcut("v")
        case .selectAll: KeyShortcut("a")
        case .findInHistory: KeyShortcut("f")
        case .findInChanges: KeyShortcut("f", [.command, .shift])
        case .commandPalette: KeyShortcut("p")
        case .showSidebar: KeyShortcut("s", [.command, .control])
        case .filterSidebar: KeyShortcut("f", [.command, .option])
        case .showToolbar: KeyShortcut("t", [.command, .option])
        // ⌘ and a number is often taken by Mission Control for switching spaces.
        case .showAllChanges: KeyShortcut("1", [.command, .option])
        case .showStagedChanges: KeyShortcut("2", [.command, .option])
        case .showUnstagedChanges: KeyShortcut("3", [.command, .option])
        case .collapseFile: KeyShortcut(KeyShortcut.leftArrowKey, [.command, .option])
        case .expandFile: KeyShortcut(KeyShortcut.rightArrowKey, [.command, .option])
        case .collapseAllFiles: KeyShortcut(KeyShortcut.leftArrowKey, [.command, .option, .shift])
        case .expandAllFiles: KeyShortcut(KeyShortcut.rightArrowKey, [.command, .option, .shift])
        case .goToNextFile: KeyShortcut(KeyShortcut.downArrowKey, [.command, .option])
        case .goToPreviousFile: KeyShortcut(KeyShortcut.upArrowKey, [.command, .option])
        case .showOnlyMissingRepositories: KeyShortcut("m", [.command, .shift])
        case .goToUncommittedChanges: KeyShortcut("u", [.command, .shift])
        case .openUncommittedChangesWindow: KeyShortcut("u", [.command, .option, .shift])
        case .checkOutBranch: KeyShortcut("b", [.command, .shift])
        case .newBranch: KeyShortcut("n", [.command, .shift])
        case .continueOperation: KeyShortcut(KeyShortcut.returnKey, [.command, .option])
        // Not ⌃⌘ with the arrows, which macOS takes for tiling windows, moving the window instead.
        case .goToPreviousConflict: KeyShortcut("[", [.command, .control])
        case .goToNextConflict: KeyShortcut("]", [.command, .control])
        case .takeOurs: KeyShortcut("o", [.command, .control])
        case .takeTheirs: KeyShortcut("t", [.command, .control])
        case .takeBoth: KeyShortcut("b", [.command, .control])
        case .markConflictResolved: KeyShortcut(KeyShortcut.returnKey, [.command, .control])
        case .stashChanges: KeyShortcut("s", [.command, .shift])
        case .stashIncludingUntracked: KeyShortcut("s", [.command, .option, .shift])
        case .commitChanges: KeyShortcut(KeyShortcut.returnKey)
        case .stageAll: KeyShortcut("a", [.command, .shift])
        case .unstageAll: KeyShortcut("a", [.command, .option, .shift])
        case .copyCommitHash: KeyShortcut("c", [.command, .shift])
        // Arrows as the sidebar's counts draw them: down for what's waiting on the remote, up for
        // what's waiting to go.
        case .fetch: KeyShortcut("f", [.command, .option, .shift])
        case .pull: KeyShortcut(KeyShortcut.downArrowKey, [.command, .option, .shift])
        case .push: KeyShortcut(KeyShortcut.upArrowKey, [.command, .option, .shift])
        case .minimize: KeyShortcut("m")
        case .showReviews: KeyShortcut("r", [.command, .shift])
        default: nil
        }
    }
}
