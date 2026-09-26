/// Something in a window the palette can jump to, such as a branch in a repository window's sidebar.
struct CommandPaletteDestination {
    enum Kind {
        case branch
        case remoteBranch
        case tag
        case stash
        case commit

        var title: String {
            switch self {
            case .branch: "Branch"
            case .remoteBranch: "Remote Branch"
            case .tag: "Tag"
            case .stash: "Stash"
            case .commit: "Commit"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let reveal: () -> Void

    func entry(isListedBeforeTyping: Bool) -> CommandPaletteEntry {
        CommandPaletteEntry(
            item: CommandPaletteItem(
                id: id,
                title: title,
                detail: kind.title,
                shortcut: nil,
                isListedBeforeTyping: isListedBeforeTyping
            ),
            action: .perform(reveal)
        )
    }
}

/// A window controller whose window holds things the palette can jump to.
protocol CommandPaletteDestinationSource: AnyObject {
    /// What the palette's first step can jump to once something is typed.
    var paletteDestinations: [CommandPaletteDestination] { get }

    /// The choices a command that asks in the palette offers, such as the branches Go to Branch…
    /// goes to. Nil for a command this window doesn't offer choices for.
    func paletteChoices(for command: AppCommand) -> [CommandPaletteDestination]?
}
