/// The sidebar's branches, remote branches, tags and stashes as places the command palette can jump
/// to, in the sidebar's order.
enum SidebarPaletteDestinations {
    static func make(from contents: SidebarContents, reveal: @escaping (SidebarItemID) -> Void) -> [CommandPaletteDestination] {
        func destination(_ id: SidebarItemID, _ kind: CommandPaletteDestination.Kind, _ title: String) -> CommandPaletteDestination {
            CommandPaletteDestination(id: paletteID(of: id), kind: kind, title: title) { reveal(id) }
        }
        let branches = contents.branches.map { destination($0.id, .branch, $0.name) }
        // Named with the remote in front, as Git names them, since several remotes can have a `main`.
        let remoteBranches = contents.remotes.flatMap { remote in
            remote.branches.map { destination($0.id, .remoteBranch, remote.name + "/" + $0.name) }
        }
        let tags = contents.tags.map { destination($0.id, .tag, $0.name) }
        let stashes = contents.stashes.map { destination($0.id, .stash, $0.message) }
        return branches + remoteBranches + tags + stashes
    }

    private static func paletteID(of id: SidebarItemID) -> String {
        switch id {
        case let .ref(name): "ref:\(name)"
        case let .remote(name): "remote:\(name)"
        case let .stash(commit): "stash:\(commit)"
        }
    }
}
