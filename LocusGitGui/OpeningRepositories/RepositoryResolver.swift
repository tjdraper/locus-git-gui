import Foundation

/// What a folder turns out to be when asked to open it.
nonisolated enum RepositoryResolution: Equatable, Sendable {
    /// The top level of the working tree the folder is in.
    case workTree(URL)
    case bare
    case notRepository
    /// macOS privacy protection kept Git out of the folder.
    case accessDenied
    /// Git's own explanation of anything else.
    case failed(String)
}

/// Finds the repository a folder belongs to, from anywhere inside it.
nonisolated enum RepositoryResolver {
    enum Answer: Equatable {
        case resolved(RepositoryResolution)
        /// Inside a repository's Git directory rather than its working tree.
        case insideGitDirectory(URL)
    }

    /// `rev-parse` prints an answer for each option in turn and stops at the first it can't give,
    /// so how far it got tells a work tree, a Git directory and a bare repository apart. Only a
    /// work tree has a top level.
    static let command = GitCommand.reading(["rev-parse", "--is-bare-repository", "--absolute-git-dir", "--show-toplevel"])

    static func resolve(_ folder: URL, with runner: GitRunner) async throws -> RepositoryResolution {
        let result = try await runner.run(command, in: folder)
        switch interpret(result) {
        case let .resolved(resolution):
            return resolution
        case let .insideGitDirectory(gitDirectory):
            // A linked worktree's or submodule's Git directory lives elsewhere, and its working
            // tree can't be found from here.
            guard gitDirectory.lastPathComponent == ".git" else {
                return .notRepository
            }
            return try await resolve(gitDirectory.deletingLastPathComponent(), with: runner)
        }
    }

    static func interpret(_ result: ChildProcess.Result) -> Answer {
        let answers = (String(bytes: result.standardOutput, encoding: .utf8) ?? "")
            .split(separator: "\n")
            .map(String.init)
        let explanation = (String(bytes: result.standardError, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if result.status == 0, answers.count == 3 {
            return .resolved(.workTree(URL(filePath: answers[2], directoryHint: .isDirectory)))
        }
        if answers.first == "true" {
            return .resolved(.bare)
        }
        if answers.count == 2, answers[0] == "false" {
            return .insideGitDirectory(URL(filePath: answers[1], directoryHint: .isDirectory))
        }
        // The system's own wording for EPERM, which is how a privacy denial reaches Git.
        if explanation.contains("Operation not permitted") {
            return .resolved(.accessDenied)
        }
        if explanation.contains("not a git repository") {
            return .resolved(.notRepository)
        }
        return .resolved(.failed(explanation))
    }
}
