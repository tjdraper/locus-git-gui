/// The branches, tags and stashes a command that asks in the palette offers, such as Check Out
/// Branch… or Drop Stash…: only the one selected in the sidebar when it's one the command takes,
/// and otherwise all of them. A command with one choice acts on it straight away, so its title
/// names it.
enum OperationPaletteChoices {
    static func choices(for command: AppCommand, in operations: RepositoryOperationsCoordinator) -> [CommandPaletteDestination]? {
        switch command {
        case .checkOutBranch, .renameBranch, .deleteBranch, .setUpstream:
            branchChoices(for: command, operations)
        case .mergeIntoCurrentBranch, .rebaseCurrentBranch:
            mergeChoices(for: command, operations)
        case .deleteTag, .applyStash, .popStash, .dropStash:
            tagAndStashChoices(for: command, operations)
        default:
            nil
        }
    }

    private static func branchChoices(
        for command: AppCommand,
        _ operations: RepositoryOperationsCoordinator
    ) -> [CommandPaletteDestination] {
        let context = operations.context
        let window = { operations.actingWindow }
        switch command {
        case .checkOutBranch:
            return narrowed(checkOutCandidates(context), operations) { id in
                if let branch = context.branch(id) {
                    operations.branches.checkOut(branch.name, from: window())
                } else {
                    operations.branches.checkOut(remoteBranch: id, from: window())
                }
            }
        case .renameBranch:
            return narrowed(localBranches(context, includingCheckedOut: true), operations) { id in
                guard let branch = context.branch(id) else { return }
                operations.branches.rename(branch.name, from: window())
            }
        case .deleteBranch:
            return narrowed(localBranches(context, includingCheckedOut: false), operations) { id in
                guard let branch = context.branch(id) else { return }
                operations.branches.delete(branch.name, from: window())
            }
        default:
            return upstreamChoices(operations)
        }
    }

    private static func mergeChoices(
        for command: AppCommand,
        _ operations: RepositoryOperationsCoordinator
    ) -> [CommandPaletteDestination] {
        let context = operations.context
        guard context.checkedOutBranch != nil else { return [] }
        return narrowed(mergeCandidates(context), operations) { id in
            guard let revision = context.revision(id) else { return }
            if command == .mergeIntoCurrentBranch {
                operations.merging.merge(revision, from: operations.actingWindow)
            } else {
                operations.merging.rebase(onto: revision, from: operations.actingWindow)
            }
        }
    }

    private static func tagAndStashChoices(
        for command: AppCommand,
        _ operations: RepositoryOperationsCoordinator
    ) -> [CommandPaletteDestination] {
        let context = operations.context
        let window = { operations.actingWindow }
        switch command {
        case .deleteTag:
            let tags = context.contents?.tags.map { destination($0.id, .tag, $0.name) } ?? []
            return narrowed(tags, operations) { id in
                guard let tag = context.tag(id) else { return }
                operations.tags.delete(tag.name, from: window())
            }
        default:
            let stashes = context.contents?.stashes.map { destination($0.id, .stash, $0.message) } ?? []
            return narrowed(stashes, operations) { id in
                guard case let .stash(commit) = id else { return }
                switch command {
                case .applyStash: operations.stashes.apply(commit, from: window())
                case .popStash: operations.stashes.pop(commit, from: window())
                default: operations.stashes.drop(commit, from: window())
                }
            }
        }
    }

    /// Named for the checked-out branch, and for the one choice when there's only one.
    static func title(for command: AppCommand, in operations: RepositoryOperationsCoordinator) -> String? {
        let context = operations.context
        let only = choices(for: command, in: operations).flatMap { $0.count == 1 ? $0.first?.title : nil }
        switch command {
        case .mergeIntoCurrentBranch:
            guard let current = context.checkedOutBranch else { return nil }
            return only.map { "Merge “\($0)” into “\(current)”" } ?? "Merge into “\(current)”…"
        case .rebaseCurrentBranch:
            guard let current = context.checkedOutBranch else { return nil }
            return only.map { "Rebase “\(current)” onto “\($0)”" } ?? "Rebase “\(current)” onto…"
        case .setUpstream:
            return upstreamBranch(operations).map { "Set Upstream of “\($0.name)”…" }
        default:
            return only.flatMap { name in actingTitle(for: command).map { "\($0) “\(name)”" + (asksFirst(command) ? "…" : "") } }
        }
    }

    /// What a command with one choice does with it, named before the choice in its title.
    private static func actingTitle(for command: AppCommand) -> String? {
        switch command {
        case .checkOutBranch: "Check Out"
        case .renameBranch: "Rename"
        case .deleteBranch: "Delete"
        case .deleteTag: "Delete Tag"
        case .applyStash: "Apply Stash"
        case .popStash: "Pop Stash"
        case .dropStash: "Drop Stash"
        default: nil
        }
    }

    /// A sheet or a confirmation still comes first.
    private static func asksFirst(_ command: AppCommand) -> Bool {
        [.renameBranch, .deleteBranch, .deleteTag, .dropStash].contains(command)
    }

    /// Local branches other than the checked-out one, then remote branches.
    private static func checkOutCandidates(_ context: OperationContext) -> [CommandPaletteDestination] {
        localBranches(context, includingCheckedOut: false) + remoteBranches(context)
    }

    private static func mergeCandidates(_ context: OperationContext) -> [CommandPaletteDestination] {
        localBranches(context, includingCheckedOut: false) + remoteBranches(context)
            + (context.contents?.tags.map { destination($0.id, .tag, $0.name) } ?? [])
    }

    private static func localBranches(_ context: OperationContext, includingCheckedOut: Bool) -> [CommandPaletteDestination] {
        (context.contents?.branches ?? [])
            .filter { includingCheckedOut || !$0.isCheckedOut }
            .map { destination($0.id, .branch, $0.name) }
    }

    private static func remoteBranches(_ context: OperationContext) -> [CommandPaletteDestination] {
        (context.contents?.remotes ?? []).flatMap { remote in
            remote.branches.map { destination($0.id, .remoteBranch, "\(remote.name)/\($0.name)") }
        }
    }

    /// The remote branches the sidebar's selected branch, or the checked-out one, can track.
    private static func upstreamChoices(_ operations: RepositoryOperationsCoordinator) -> [CommandPaletteDestination] {
        guard let branch = upstreamBranch(operations) else { return [] }
        return remoteBranches(operations.context)
            .filter { $0.title != branch.upstream }
            .map { remote in
                CommandPaletteDestination(id: remote.id, kind: .remoteBranch, title: remote.title) { [weak operations] in
                    let fullName = String(remote.id.dropFirst("ref:".count))
                    operations?.branches.setUpstream(of: branch.name, to: fullName, named: remote.title, from: operations?.actingWindow)
                }
            }
    }

    private static func upstreamBranch(_ operations: RepositoryOperationsCoordinator) -> SidebarContents.Branch? {
        let context = operations.context
        if let selection = operations.sidebarSelection(), let branch = context.branch(selection) {
            return branch
        }
        return context.contents?.branches.first(where: \.isCheckedOut)
    }

    /// Only the sidebar's selection when it's among them.
    private static func narrowed(
        _ candidates: [CommandPaletteDestination],
        _ operations: RepositoryOperationsCoordinator,
        act: @escaping (SidebarItemID) -> Void
    ) -> [CommandPaletteDestination] {
        let selected = operations.sidebarSelection().map(paletteID)
        let chosen = candidates.first { $0.id == selected }.map { [$0] } ?? candidates
        return chosen.map { candidate in
            CommandPaletteDestination(id: candidate.id, kind: candidate.kind, title: candidate.title) {
                guard let id = sidebarID(candidate.id) else { return }
                act(id)
            }
        }
    }

    private static func destination(
        _ id: SidebarItemID,
        _ kind: CommandPaletteDestination.Kind,
        _ title: String
    ) -> CommandPaletteDestination {
        CommandPaletteDestination(id: paletteID(id), kind: kind, title: title) {
            // Replaced by `narrowed` with what the command does.
        }
    }

    private static func paletteID(_ id: SidebarItemID) -> String {
        switch id {
        case let .ref(name): "ref:\(name)"
        case let .remote(name): "remote:\(name)"
        case let .stash(commit): "stash:\(commit)"
        }
    }

    private static func sidebarID(_ paletteID: String) -> SidebarItemID? {
        if paletteID.hasPrefix("ref:") {
            return .ref(String(paletteID.dropFirst(4)))
        }
        if paletteID.hasPrefix("stash:") {
            return .stash(String(paletteID.dropFirst(6)))
        }
        return nil
    }
}
