import Foundation

/// Everything the window shows about a repository, read in one go.
nonisolated struct RepositorySnapshot: Equatable, Sendable {
    /// `git status` failed, or wrote something that couldn't be read. Git's output is kept whole,
    /// since it is the part people can search for.
    struct ReadFailure: Error, Equatable {
        let result: ChildProcess.Result
        let outputWasUnreadable: Bool
    }

    let status: RepositoryStatus
    let operation: InProgressOperation?

    static func read(
        _ repository: Repository,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> RepositorySnapshot {
        let result = try await run(RepositoryStatus.command)
        guard result.status == 0 else {
            throw ReadFailure(result: result, outputWasUnreadable: false)
        }
        let status: RepositoryStatus
        do {
            status = try RepositoryStatus(parsing: result.standardOutput)
        } catch {
            throw ReadFailure(result: result, outputWasUnreadable: true)
        }
        return RepositorySnapshot(status: status, operation: InProgressOperation.read(gitDirectory: repository.gitDirectory))
    }
}
