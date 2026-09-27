/// Something in a window the palette can jump to, such as a branch in a repository window's sidebar.
struct CommandPaletteDestination {
    enum Kind {
        case branch
        case remoteBranch
        case tag
        case stash
        case commit
        case remote

        var title: String {
            switch self {
            case .branch: "Branch"
            case .remoteBranch: "Remote Branch"
            case .tag: "Tag"
            case .stash: "Stash"
            case .commit: "Commit"
            case .remote: "Remote"
            }
        }
    }

    /// A second choice the command needs once this one is made, such as the remote a tag is pushed to.
    struct NextStep {
        let placeholder: String
        let choices: [CommandPaletteDestination]
    }

    let id: String
    let kind: Kind
    let title: String
    /// Asked before `reveal`, unless it has only the one choice, which is taken.
    var next: NextStep?
    let reveal: () -> Void

    init(id: String, kind: Kind, title: String, next: NextStep? = nil, reveal: @escaping () -> Void) {
        self.id = id
        self.kind = kind
        self.title = title
        self.next = next
        self.reveal = reveal
    }

    func entry(isListedBeforeTyping: Bool) -> CommandPaletteEntry {
        CommandPaletteEntry(item: item(isListedBeforeTyping: isListedBeforeTyping), action: action)
    }

    private var action: CommandPaletteEntry.Action {
        guard let next else { return .perform(reveal) }
        if let only = next.choices.first, next.choices.count == 1 {
            return only.action
        }
        return .ask {
            CommandPaletteStep(placeholder: next.placeholder, entries: next.choices.map { $0.entry(isListedBeforeTyping: true) })
        }
    }

    private func item(isListedBeforeTyping: Bool) -> CommandPaletteItem {
        CommandPaletteItem(id: id, title: title, detail: kind.title, shortcut: nil, isListedBeforeTyping: isListedBeforeTyping)
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
