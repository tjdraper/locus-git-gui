import AppKit

nonisolated extension AppCommand {
    /// Named with how many repositories it acts on, for a command that acts on the dashboard's
    /// selection.
    func title(count: Int) -> String {
        switch self {
        case .openSelectedRepositories: count > 1 ? "Open \(count) Repositories" : "Open Repository"
        case .removeSelectedRepositories: count > 1 ? "Remove \(count) Repositories from List" : "Remove Repository from List"
        default: title
        }
    }

    /// The shortcut in the menus, which for the two Copy Path commands depends on which path the
    /// user wants ⌥⌘C to copy. The other one takes ⌥⇧⌘C.
    func shortcut(optionCommandCCopiesPathFromRoot: Bool) -> KeyShortcut? {
        guard optionCommandCCopiesPathFromRoot else { return shortcut }
        switch self {
        case .copyAbsolutePath: return AppCommand.copyPathFromRepositoryRoot.shortcut
        case .copyPathFromRepositoryRoot: return AppCommand.copyAbsolutePath.shortcut
        default: return shortcut
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
