import Foundation

/// What the dashboard says about a repository on the recent list, checked each time it opens.
nonisolated enum RecentRepositoryState: Equatable, Sendable {
    case onBranch(String)
    case detached(commit: String)
    /// Moved or deleted, or its folder is no longer the top of a repository.
    case missing
    /// macOS privacy protection kept Git out of the folder.
    case accessDenied
    /// Git's own explanation of anything else.
    case failed(String)

    /// Exits 1 when HEAD is detached. Unlike `rev-parse`, it names the branch before its first commit.
    static let branchCommand = GitCommand.reading(["symbolic-ref", "--quiet", "--short", "HEAD"])
    static let commitCommand = GitCommand.reading(["rev-parse", "--short", "HEAD"])

    /// Runs its commands in the repository's working tree.
    static func read(
        _ repository: Repository,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> RecentRepositoryState {
        guard FileManager.default.fileExists(atPath: repository.workTree.path) else {
            return .missing
        }
        do {
            let resolution = RepositoryResolver.interpret(try await run(RepositoryResolver.command))
            switch resolution {
            case let .resolved(.repository(found)) where found.id == repository.id:
                return try await readBranch(of: found, running: run)
            case .resolved(.accessDenied):
                return .accessDenied
            case let .resolved(.failed(output)):
                return .failed(output)
            case .resolved(.repository), .resolved(.bare), .resolved(.notRepository), .insideGitDirectory:
                return .missing
            }
        } catch let ChildProcess.Failure.couldNotStart(error) {
            return couldNotStart(in: repository.workTree, because: error)
        }
    }

    private static func readBranch(
        of repository: Repository,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> RecentRepositoryState {
        let branch = try await run(branchCommand)
        if branch.status == 0 {
            return .onBranch(text(branch.standardOutput))
        }
        guard branch.status == 1 else {
            return .failed(text(branch.standardError))
        }
        // A rebase detaches HEAD while it runs, but the branch it is rebasing is the one that matters.
        if case let .rebasing(name?, _, _) = InProgressOperation.read(gitDirectory: repository.gitDirectory) {
            return .onBranch(name)
        }
        let commit = try await run(commitCommand)
        guard commit.status == 0 else {
            return .failed(text(commit.standardError))
        }
        return .detached(commit: text(commit.standardOutput))
    }

    /// Git never ran, so the system's reason stands in for Git's.
    private static func couldNotStart(in folder: URL, because error: any Error) -> RecentRepositoryState {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) {
            return .accessDenied
        }
        if !FileManager.default.fileExists(atPath: folder.path) {
            return .missing
        }
        return .failed(error.localizedDescription)
    }

    private static func text(_ output: Data) -> String {
        (String(bytes: output, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
