import Foundation

/// Runs Git in one repository and records every command in the repository's activity.
final class RepositoryCommandRunner {
    /// There is no Git to run. The app's missing-Git notice tells the user, so callers stay quiet.
    struct NoUsableGit: Error {}

    let repository: Repository
    let log: GitCommandLog
    private let gitChoice: GitChoiceStore
    private let checkForMissingGit: () -> Void

    init(repository: Repository, log: GitCommandLog, gitChoice: GitChoiceStore, checkForMissingGit: @escaping () -> Void) {
        self.repository = repository
        self.log = log
        self.gitChoice = gitChoice
        self.checkForMissingGit = checkForMissingGit
    }

    func run(_ command: GitCommand) async throws -> ChildProcess.Result {
        try await run(command, onOutput: nil)
    }

    /// `onOutput` is handed Git's standard output as it arrives, for a caller that shows it before
    /// the command has finished.
    func run(_ command: GitCommand, onOutput: ((Data) -> Void)?) async throws -> ChildProcess.Result {
        guard let runner = await gitChoice.runner() else {
            throw NoUsableGit()
        }
        let startedAt = Date()
        let started = ContinuousClock.now
        func record(_ outcome: GitLogEntry.Outcome) {
            log.record(GitLogEntry(
                startedAt: startedAt,
                executable: runner.executableURL,
                arguments: command.arguments,
                duration: ContinuousClock.now - started,
                outcome: outcome
            ))
        }

        // Run as a task of its own, so the Activity window can cancel it as well as its caller.
        let directory = repository.workTree
        let task = Task {
            guard let onOutput else {
                return try await runner.run(command, in: directory)
            }
            return try await Self.collect(runner.stream(command, in: directory), onOutput: onOutput)
        }
        let running = log.begin(command.arguments, at: startedAt) { task.cancel() }
        defer { log.end(running) }

        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            record(.exited(result))
            return result
        } catch let ChildProcess.Failure.couldNotStart(error) {
            record(.couldNotStart(error.localizedDescription))
            // Git can fail to start because it's gone, or because the repository's folder is.
            guard await GitInstallation.isUsable(runner.executableURL, environment: runner.environment) else {
                checkForMissingGit()
                throw NoUsableGit()
            }
            throw ChildProcess.Failure.couldNotStart(error)
        } catch {
            record(.cancelled)
            throw error
        }
    }

    private static func collect(
        _ events: AsyncThrowingStream<ChildProcess.Event, any Error>,
        onOutput: (Data) -> Void
    ) async throws -> ChildProcess.Result {
        var standardOutput = Data()
        var standardError = Data()
        for try await event in events {
            switch event {
            case let .standardOutput(data):
                standardOutput.append(data)
                onOutput(data)
            case let .standardError(data):
                standardError.append(data)
            case let .exited(status):
                return ChildProcess.Result(status: status, standardOutput: standardOutput, standardError: standardError)
            }
        }
        // The stream only ends without an exit when the task was cancelled.
        throw CancellationError()
    }
}
