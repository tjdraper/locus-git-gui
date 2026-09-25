import Foundation

/// What the title bar shows about a repository, read in one go.
nonisolated struct RepositorySnapshot: Equatable, Sendable {
    let status: RepositoryStatus
    let operation: InProgressOperation?

    static func read(
        _ repository: Repository,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> RepositorySnapshot {
        let status = try await GitReadFailure.read("status", with: RepositoryStatus.command, running: run) { output in
            try RepositoryStatus(parsing: output)
        }
        return RepositorySnapshot(status: status, operation: InProgressOperation.read(gitDirectory: repository.gitDirectory))
    }
}
