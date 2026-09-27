import AppKit

/// Runs the commands that change branches, stashes, tags and history, in the working area's queue so
/// they take turns with staging and committing. A failure shows as a sheet on the window the
/// command was started from, with the next steps it offers.
final class OperationRunner {
    /// A step that exited with an error, which stops the steps after it.
    struct Failed: Error {
        let failure: GitFailure
    }

    /// What an operation's body runs each Git command through.
    struct Steps {
        let commands: RepositoryCommandRunner

        /// Throws `Failed`, with `summary` saying what failed, when Git exits with an error.
        @discardableResult
        func run(_ command: GitCommand, failing summary: String) async throws -> ChildProcess.Result {
            let result = try await commands.run(command)
            guard result.status == 0 else {
                throw Failed(failure: GitFailure(summary: summary, arguments: command.arguments, result: result))
            }
            return result
        }

        /// For a command whose exit status is itself the answer.
        func read(_ command: GitCommand) async throws -> ChildProcess.Result {
            try await commands.run(command)
        }
    }

    /// Shows a failure on the window the command was started from.
    var present: ((GitFailure, NSWindow?, _ retry: (() -> Void)?, GitFailureNextSteps) -> Void)?
    /// What every failure offers: Show Conflicts, which takes the repository's window to them.
    var showConflicts: (() -> Void)?
    let commands: RepositoryCommandRunner
    private let queue: WorkingAreaCommandQueue

    init(commands: RepositoryCommandRunner, queue: WorkingAreaCommandQueue) {
        self.commands = commands
        self.queue = queue
    }

    /// `nextSteps` adds what a failure offers beyond Show Conflicts, such as Stash and Continue.
    func perform(
        from window: NSWindow?,
        retry: (() -> Void)? = nil,
        nextSteps: @escaping (GitFailure) -> GitFailureNextSteps = { _ in GitFailureNextSteps() },
        _ body: @escaping (Steps) async throws -> Void
    ) {
        let steps = Steps(commands: commands)
        queue.run("") { [weak self] in
            do {
                try await body(steps)
            } catch let failed as Failed {
                self?.show(failed.failure, from: window, retry: retry, nextSteps: nextSteps(failed.failure))
            } catch let ChildProcess.Failure.couldNotStart(error) {
                // Git never ran, so there is no output of its own. The system's reason stands in for it.
                let failure = GitFailure(
                    summary: "Git couldn’t start.",
                    arguments: [],
                    result: ChildProcess.Result(status: -1, standardOutput: Data(), standardError: Data(error.localizedDescription.utf8))
                )
                self?.show(failure, from: window, retry: retry, nextSteps: GitFailureNextSteps())
            }
        }
    }

    /// Offers Stash and Continue when uncommitted changes are in the way, which `stashAndContinue`
    /// carries out, told whether untracked files are among them.
    func perform(
        from window: NSWindow?,
        stashAndContinue: @escaping (_ includesUntracked: Bool) -> Void,
        body: @escaping (Steps) async throws -> Void
    ) {
        let nextSteps = { (failure: GitFailure) -> GitFailureNextSteps in
            guard case let .localChangesWouldBeOverwritten(_, includesUntracked) = failure.recognized else { return GitFailureNextSteps() }
            return GitFailureNextSteps(stashAndContinue: { stashAndContinue(includesUntracked) })
        }
        perform(from: window, nextSteps: nextSteps, body)
    }

    private func show(_ failure: GitFailure, from window: NSWindow?, retry: (() -> Void)?, nextSteps: GitFailureNextSteps) {
        var nextSteps = nextSteps
        nextSteps.showConflicts = nextSteps.showConflicts ?? showConflicts
        present?(failure, window, retry, nextSteps)
    }
}
