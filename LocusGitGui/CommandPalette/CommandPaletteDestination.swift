/// Something in a window the palette can jump to, such as a branch in a repository window's sidebar.
struct CommandPaletteDestination {
    enum Kind {
        case branch
        case remoteBranch
        case tag
        case stash

        var title: String {
            switch self {
            case .branch: "Branch"
            case .remoteBranch: "Remote Branch"
            case .tag: "Tag"
            case .stash: "Stash"
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
    var paletteDestinations: [CommandPaletteDestination] { get }
}
