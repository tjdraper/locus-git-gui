/// One row the command palette can offer: a menu command, or something in the window to jump to.
nonisolated struct CommandPaletteItem: Equatable, Sendable {
    /// Stays the same when the title changes, such as a menu item AppKit retitles from Show to Hide,
    /// so the palette's history still finds it.
    let id: String
    let title: String
    /// The menu a command is in, or the kind of thing a jump goes to.
    let detail: String
    /// As the menu bar draws it, such as ⌥⌘F.
    let shortcut: String?
    /// A jump among every branch and tag would bury the commands, so jumps wait for a search.
    let isListedBeforeTyping: Bool
}
