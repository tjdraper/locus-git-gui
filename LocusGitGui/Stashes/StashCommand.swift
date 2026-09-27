/// The Git commands that stash changes and bring them back. A stash is named by its place in the
/// list, `stash@{n}`, which `pop` and `drop` need, found again from its commit just before running,
/// since stashes made meanwhile renumber it.
nonisolated enum StashCommand {
    /// Staged and unstaged changes, and untracked files too when `includingUntracked`.
    static func stash(message: String, includingUntracked: Bool) -> GitCommand {
        .changing(["stash", "push"] + (includingUntracked ? ["--include-untracked"] : []) + (message.isEmpty ? [] : ["--message", message]))
    }

    /// By commit, which `apply` takes as it takes an entry of the list.
    static func apply(_ commit: String) -> GitCommand {
        .changing(["stash", "apply", commit])
    }

    static func pop(at index: Int) -> GitCommand {
        .changing(["stash", "pop", "stash@{\(index)}"])
    }

    static func drop(at index: Int) -> GitCommand {
        .changing(["stash", "drop", "stash@{\(index)}"])
    }

    /// Puts a dropped stash back in the list.
    static func store(_ commit: String, message: String) -> GitCommand {
        .changing(["stash", "store", "--message", message, commit])
    }

    /// Where the stash made by `commit` is in the list now, or nil when it's gone.
    static func index(of commit: String, running run: (GitCommand) async throws -> ChildProcess.Result) async throws -> Int? {
        let stashes = try await GitReadFailure.read("stashes", with: Stash.listCommand, running: run, parse: Stash.parseList)
        return stashes.firstIndex { $0.commit == commit }
    }
}
