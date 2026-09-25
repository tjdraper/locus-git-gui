import Foundation

/// Everything the window shows about a repository, read in one go.
nonisolated struct RepositorySnapshot: Equatable, Sendable {
    /// `git status` failed. Git's output is kept whole, since it is the part people can search for.
    struct ReadFailure: Error, Equatable {
        let result: ChildProcess.Result
    }

    let status: RepositoryStatus
    let operation: InProgressOperation?

    static func read(_ repository: Repository, with runner: GitRunner) async throws -> RepositorySnapshot {
        let result = try await runner.run(RepositoryStatus.command, in: repository.workTree)
        guard result.status == 0 else {
            throw ReadFailure(result: result)
        }
        return RepositorySnapshot(
            status: try RepositoryStatus(parsing: result.standardOutput),
            operation: InProgressOperation.read(gitDirectory: repository.gitDirectory)
        )
    }
}
