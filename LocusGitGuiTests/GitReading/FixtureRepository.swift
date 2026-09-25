import Foundation

/// A throwaway repository the tests build with the real `git`, isolated from the global and
/// system Git config on this Mac so a setting such as `commit.gpgsign` can't change the outcome.
struct FixtureRepository {
    struct GitFailed: Error, CustomStringConvertible {
        let arguments: [String]
        let result: ChildProcess.Result

        var description: String {
            "git \(arguments.joined(separator: " ")) exited \(result.status): "
                + (String(bytes: result.standardError, encoding: .utf8) ?? "")
        }
    }

    static let environment: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_AUTHOR_NAME"] = "Test Author"
        environment["GIT_AUTHOR_EMAIL"] = "author@example.com"
        environment["GIT_COMMITTER_NAME"] = "Test Author"
        environment["GIT_COMMITTER_EMAIL"] = "author@example.com"
        return environment
    }()

    let folder: URL

    static func make() async throws -> FixtureRepository {
        let repository = try FixtureRepository(folder: TestGit.makeScratchFolder())
        try await repository.git("init", "--quiet", "--initial-branch=main")
        return repository
    }

    /// A clone in a sibling scratch folder, with `origin` pointing back at this repository.
    func clone() async throws -> FixtureRepository {
        let clone = try FixtureRepository(folder: TestGit.makeScratchFolder())
        try await git("clone", "--quiet", folder.path, clone.folder.path)
        return clone
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    func git(_ arguments: String..., environment extra: [String: String] = [:]) async throws -> String {
        let result = try await run(.changing(arguments), environment: extra)
        guard result.status == 0 else {
            throw GitFailed(arguments: arguments, result: result)
        }
        return String(bytes: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func run(_ command: GitCommand, environment extra: [String: String] = [:]) async throws -> ChildProcess.Result {
        let runner = GitRunner(
            executableURL: TestGit.executableURL,
            environment: Self.environment.merging(extra) { _, new in new }
        )
        return try await runner.run(command, in: folder)
    }

    func write(_ text: String, to path: String) throws {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func commit(_ message: String, writing text: String, to path: String) async throws {
        try write(text, to: path)
        try await git("add", "--", path)
        try await git("commit", "--quiet", "--message", message)
    }
}
