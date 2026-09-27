/// The sidebar's items and the selected commit's parents and labels, for the command palette.
extension RepositoryWindowController: CommandPaletteDestinationSource {
    var paletteDestinations: [CommandPaletteDestination] {
        guard let contents = sidebar.contents else { return [] }
        return SidebarPaletteDestinations.make(from: contents) { [weak self] id in self?.revealInSidebar(id) }
    }

    func paletteChoices(for command: AppCommand) -> [CommandPaletteDestination]? {
        let kinds: Set<CommandPaletteDestination.Kind>
        switch command {
        case .goToBranch: kinds = [.branch, .remoteBranch]
        case .goToTag: kinds = [.tag]
        case .goToStash: kinds = [.stash]
        case .goToParentCommit: return commitColumns.history.parentChoices
        case .revealCommitInSidebar: return commitColumns.history.labelChoices
        default:
            return OperationPaletteChoices.choices(for: command, in: operations)
                ?? remotes.paletteChoices(for: command, selection: sidebar.selection)
        }
        return paletteDestinations.filter { kinds.contains($0.kind) }
    }

    func menuTitle(for command: AppCommand) -> String? {
        OperationPaletteChoices.title(for: command, in: operations)
    }
}
