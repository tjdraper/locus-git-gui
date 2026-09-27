import Foundation

/// Stash and Continue for a command that uncommitted changes are in the way of: the changes are put
/// aside, the command runs, and they come back afterwards. Merges and rebases use Git's own
/// `--autostash` instead, which waits for them to finish even when they stop on conflicts.
enum LocalChangesStash {
    private static let latestStash = GitCommand.reading(["rev-parse", "--quiet", "--verify", "refs/stash"])

    /// `purpose` finishes “Stashed by Locus Git Gui before…”, which names the stash in the list.
    static func around(
        _ purpose: String,
        includingUntracked: Bool,
        steps: OperationRunner.Steps,
        _ body: () async throws -> Void
    ) async throws {
        let before = try await latest(steps)
        try await steps.run(
            StashCommand.stash(message: "Stashed by Locus Git Gui before \(purpose)", includingUntracked: includingUntracked),
            failing: "Git couldn’t put the changes aside."
        )
        // `git stash` makes nothing when there's nothing to put aside, and the stash on top is then an
        // older one, which mustn't be popped.
        guard let stash = try await latest(steps), stash != before else {
            try await body()
            return
        }
        do {
            try await body()
        } catch let failed as OperationRunner.Failed {
            // A command that stopped on conflicts has changed the files, which the changes can't come
            // back into until it's finished.
            if failed.failure.recognized != .stoppedOnConflicts, (try? await pop(stash, steps: steps)) == true {
                throw failed
            }
            throw OperationRunner.Failed(failure: GitFailure(
                summary: failed.failure.summary + " The changes put aside for it are kept in the stash list.",
                arguments: failed.failure.arguments,
                result: failed.failure.result
            ))
        } catch {
            // Such as the command being cancelled from the Activity window, which would otherwise
            // leave the changes in the stash list without a word.
            _ = try? await pop(stash, steps: steps)
            throw error
        }
        guard let index = try await StashCommand.index(of: stash, running: steps.commands.run) else { return }
        try await steps.run(StashCommand.pop(at: index), failing: "Git couldn’t bring back the changes it put aside.")
    }

    private static func pop(_ stash: String, steps: OperationRunner.Steps) async throws -> Bool {
        guard let index = try await StashCommand.index(of: stash, running: steps.commands.run) else { return false }
        return try await steps.read(StashCommand.pop(at: index)).status == 0
    }

    private static func latest(_ steps: OperationRunner.Steps) async throws -> String? {
        let result = try await steps.read(latestStash)
        guard result.status == 0 else { return nil }
        return String(bytes: result.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
