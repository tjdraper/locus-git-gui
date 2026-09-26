/// What staging, unstaging and discarding do with files picked together, which can come from
/// different groups: each acts on the picked files it applies to, and says how many.
nonisolated struct StagingTargets {
    enum Toggle: Equatable {
        case stage([DiffFile])
        case unstage([DiffFile])
        /// Staging a conflicted file marks it resolved.
        case resolve([DiffFile])
    }

    let files: [DiffFile]

    var toStage: [DiffFile] {
        files.filter { [.unstaged, .untracked].contains(WorkingAreaGroup($0)) }
    }

    var toUnstage: [DiffFile] {
        files.filter { WorkingAreaGroup($0) == .staged }
    }

    var toResolve: [DiffFile] {
        files.filter { WorkingAreaGroup($0) == .conflicted }
    }

    var toDiscard: [DiffFile] {
        files.filter { [.unstaged, .untracked].contains(WorkingAreaGroup($0)) }
    }

    /// What Space and Stage File do: stage whatever picked isn't staged, and unstage when it all is.
    /// Conflicts are only marked resolved when they're all that's picked.
    var toggle: Toggle? {
        if !toStage.isEmpty {
            return .stage(toStage)
        }
        if !toResolve.isEmpty {
            return .resolve(toResolve)
        }
        return toUnstage.isEmpty ? nil : .unstage(toUnstage)
    }

    var toggleTitle: String {
        switch toggle {
        case let .stage(files): Self.title("Stage", files, one: "Stage File")
        case let .unstage(files): Self.title("Unstage", files, one: "Unstage File")
        case let .resolve(files): files.count > 1 ? "Mark \(files.count) Files as Resolved" : "Mark as Resolved"
        case nil: "Stage File"
        }
    }

    var discardTitle: String {
        let files = toDiscard
        guard !files.isEmpty, files.allSatisfy({ WorkingAreaGroup($0) == .untracked }) else {
            return files.count > 1 ? "Discard \(files.count) Files…" : "Discard Changes…"
        }
        return files.count > 1 ? "Move \(files.count) Files to Trash…" : "Move to Trash…"
    }

    /// A file header's buttons, which are short when they act on that one file.
    var stageButtonTitle: String {
        files.count == 1 ? "Stage" : Self.title("Stage", toStage, one: "Stage")
    }

    var unstageButtonTitle: String {
        files.count == 1 ? "Unstage" : Self.title("Unstage", toUnstage, one: "Unstage")
    }

    var resolveButtonTitle: String {
        toResolve.count > 1 ? "Mark \(toResolve.count) Resolved" : "Mark Resolved"
    }

    var discardButtonTitle: String {
        guard files.count == 1, let file = files.first else { return discardTitle }
        return WorkingAreaGroup(file) == .untracked ? "Move to Trash…" : "Discard…"
    }

    static func title(_ verb: String, _ files: [DiffFile], one: String) -> String {
        files.count > 1 ? "\(verb) \(files.count) Files" : one
    }
}
