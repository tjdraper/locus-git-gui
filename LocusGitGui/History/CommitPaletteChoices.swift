/// A commit's parents and labels as choices for Go to Parent and Reveal in Sidebar, wherever a
/// commit is shown: the history, or a commit's own window.
enum CommitPaletteChoices {
    static func parents(of commit: Commit?, title: (String) -> String, goTo: @escaping (String) -> Void) -> [CommandPaletteDestination] {
        (commit?.parents ?? []).map { hash in
            CommandPaletteDestination(id: "commit:\(hash)", kind: .commit, title: title(hash)) { goTo(hash) }
        }
    }

    /// HEAD isn't in the sidebar, so it's left out.
    static func labels(_ labels: [CommitRefLabel], reveal: @escaping (SidebarItemID) -> Void) -> [CommandPaletteDestination] {
        labels.compactMap { label in
            guard let item = label.sidebarItem, case let .ref(name) = item else { return nil }
            let kind: CommandPaletteDestination.Kind = switch label.kind {
            case .remoteBranch: .remoteBranch
            case .tag: .tag
            case .head, .checkedOutBranch, .branch: .branch
            }
            return CommandPaletteDestination(id: "ref:\(name)", kind: kind, title: label.name) { reveal(item) }
        }
    }
}
