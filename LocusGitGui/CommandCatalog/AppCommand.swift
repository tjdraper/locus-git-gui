import AppKit

/// Every command the app offers. The menu bar, context menus and the command palette all take a
/// command's title and shortcut from here, so they can't disagree about what it's called or
/// which keys reach it. Its action is in `AppCommandAction`, which reaches into the rest of the app.
nonisolated enum AppCommand: String, CaseIterable, Sendable {
    case about
    case checkForUpdates
    case hide
    case hideOthers
    case showAll
    case quit

    case newTab
    case open
    case showDashboard
    case openSelectedRepositories
    case removeSelectedRepositories
    case removeAllMissingRepositories
    case showRepositoryInFinder
    case setDisplayName
    case close

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
    case showToolbar
    case customizeToolbar
    case goToBranch
    case goToTag
    case goToStash
    case showGitLog
    case showOnlyMissingRepositories

    case openCommitInNewWindow
    case copyCommitHash
    case copyCommitSubject
    case goToParentCommit
    case revealCommitInSidebar
    case showFullMessage

    case minimize
    case zoom
    case bringAllToFront

    case setupChecklist

    var title: String {
        switch self {
        case .about: "About Locus Git Gui"
        case .checkForUpdates: "Check for Updates…"
        case .hide: "Hide Locus Git Gui"
        case .hideOthers: "Hide Others"
        case .showAll: "Show All"
        case .quit: "Quit Locus Git Gui"
        case .newTab: "New Tab"
        case .open: "Open…"
        case .showDashboard: "Show Dashboard"
        case .openSelectedRepositories: title(count: 1)
        case .removeSelectedRepositories: title(count: 1)
        case .removeAllMissingRepositories: "Remove All Missing Repositories"
        case .showRepositoryInFinder: "Show in Finder"
        case .setDisplayName: "Set Display Name…"
        case .close: "Close"
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
        case .showToolbar: "Show Toolbar"
        case .customizeToolbar: "Customize Toolbar…"
        case .goToBranch: "Go to Branch…"
        case .goToTag: "Go to Tag…"
        case .goToStash: "Go to Stash…"
        case .showGitLog: "Show Git Log"
        case .showOnlyMissingRepositories: "Show Only Missing Repositories"
        case .openCommitInNewWindow: "Open in New Window"
        case .copyCommitHash: "Copy Hash"
        case .copyCommitSubject: "Copy Subject"
        case .goToParentCommit: "Go to Parent"
        case .revealCommitInSidebar: "Reveal in Sidebar"
        case .showFullMessage: "Show Full Message"
        case .minimize: "Minimize"
        case .zoom: "Zoom"
        case .bringAllToFront: "Bring All to Front"
        case .setupChecklist: "Setup Checklist"
        }
    }

    /// Named with how many repositories it acts on, for a command that acts on the dashboard's
    /// selection.
    func title(count: Int) -> String {
        switch self {
        case .openSelectedRepositories: count > 1 ? "Open \(count) Repositories" : "Open Repository"
        case .removeSelectedRepositories: count > 1 ? "Remove \(count) Repositories from List" : "Remove Repository from List"
        default: title
        }
    }

    var shortcut: KeyShortcut? {
        switch self {
        case .hide: KeyShortcut("h")
        case .hideOthers: KeyShortcut("h", [.command, .option])
        case .quit: KeyShortcut("q")
        case .newTab: KeyShortcut("t")
        case .open: KeyShortcut("o")
        case .showDashboard: KeyShortcut("o", [.command, .shift])
        case .openSelectedRepositories: KeyShortcut(KeyShortcut.returnKey, [])
        case .removeSelectedRepositories: KeyShortcut(KeyShortcut.deleteKey)
        case .removeAllMissingRepositories: KeyShortcut(KeyShortcut.deleteKey, [.command, .option])
        case .showRepositoryInFinder: KeyShortcut(KeyShortcut.returnKey)
        case .close: KeyShortcut("w")
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
        case .showOnlyMissingRepositories: KeyShortcut("m", [.command, .shift])
        case .copyCommitHash: KeyShortcut("c", [.command, .shift])
        case .minimize: KeyShortcut("m")
        default: nil
        }
    }

    /// A second shortcut for the same command, on a hidden menu item of its own, since a menu item
    /// has only one.
    var alternateShortcut: KeyShortcut? {
        switch self {
        case .showDashboard: KeyShortcut("o", [.command, .shift, .option])
        case .commandPalette: KeyShortcut("p", [.command, .shift])
        default: nil
        }
    }
}
