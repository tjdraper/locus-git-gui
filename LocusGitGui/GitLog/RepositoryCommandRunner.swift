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
        try await perform(command) { runner, directory in
            guard let onOutput else {
                return (try await runner.run(command, in: directory), ())
            }
            return (try await Self.collect(runner.stream(command, in: directory), onOutput: onOutput), ())
        }.result
    }

    /// Reads a patch as Git writes it, away from the main actor, without keeping the output itself,
    /// which for a large commit can be hundreds of megabytes. The result's standard output is empty.
    func readPatch(_ command: GitCommand, limits: PatchParser.Limits) async throws -> (result: ChildProcess.Result, files: [FilePatch]) {
        let (result, files) = try await perform(command) { runner, directory in
            try await Self.parsePatch(runner.stream(command, in: directory), parser: PatchParser(limits: limits))
        }
        return (result, files)
    }

    private func perform<Value: Sendable>(
        _ command: GitCommand,
        _ body: @escaping (GitRunner, URL) async throws -> (ChildProcess.Result, Value)
    ) async throws -> (result: ChildProcess.Result, value: Value) {
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
            try await body(runner, directory)
        }
        let running = log.begin(command.arguments, at: startedAt) { task.cancel() }
        defer { log.end(running) }

        do {
            let (result, value) = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            record(.exited(result))
            return (result, value)
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

    @concurrent
    private nonisolated static func parsePatch(
        _ events: AsyncThrowingStream<ChildProcess.Event, any Error>,
        parser: PatchParser
    ) async throws -> (ChildProcess.Result, [FilePatch]) {
        var parser = parser
        var standardError = Data()
        for try await event in events {
            switch event {
            case let .standardOutput(data):
                parser.consume(data)
            case let .standardError(data):
                standardError.append(data)
            case let .exited(status):
                return (ChildProcess.Result(status: status, standardOutput: Data(), standardError: standardError), parser.finish())
            }
        }
        throw CancellationError()
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
