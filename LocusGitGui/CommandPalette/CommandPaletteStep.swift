/// What the palette offers at one point: every command to begin with, then, for a command that
/// needs an argument, the choices for it.
struct CommandPaletteStep {
    let placeholder: String
    let entries: [CommandPaletteEntry]
    let search: CommandPaletteSearch

    init(placeholder: String, entries: [CommandPaletteEntry]) {
        self.placeholder = placeholder
        self.entries = entries
        search = CommandPaletteSearch(items: entries.map(\.item))
    }
}

/// A row in a palette step and what choosing it does.
struct CommandPaletteEntry {
    enum Action {
        case perform(() -> Void)
        /// Stays in the palette and asks for the command's argument.
        case ask(() -> CommandPaletteStep)
    }

    let item: CommandPaletteItem
    let action: Action
}
