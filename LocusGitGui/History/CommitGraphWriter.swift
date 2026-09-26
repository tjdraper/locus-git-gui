import Foundation
import os

/// Writes a repository's commit-graph file when it has none, in the background as the repository
/// opens. Without it, Git walks a large history from end to end before it can list a page of it in
/// order. It's a cache Git keeps for itself, the same one `git gc` and `git maintenance` write, and
/// changes nothing the user sees.
final class CommitGraphWriter {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "CommitGraph")
    /// `--split` adds a small layer on top when the file is written again later, rather than
    /// rewriting it. `--changed-paths` makes a history of one file fast.
    static let writeCommand = GitCommand.changing(["commit-graph", "write", "--reachable", "--split", "--changed-paths"])
    /// Where the file lives, which for a linked worktree is in the main repository's Git directory.
    static let folderCommand = GitCommand.reading(["rev-parse", "--git-path", "objects/info"])

    /// How long to wait for another Git process in the repository to finish before trying again.
    nonisolated private static let busyWait: Duration = .seconds(2)
    /// A process that never ends, such as one waiting on input in Terminal, isn't waited on forever.
    nonisolated private static let longestWait: Duration = .seconds(60)

    private let repository: Repository
    private let run: (GitCommand) async throws -> ChildProcess.Result
    private var writing: Task<Void, Never>?

    init(repository: Repository, run: @escaping (GitCommand) async throws -> ChildProcess.Result) {
        self.repository = repository
        self.run = run
    }

    func writeIfMissing() {
        guard writing == nil else { return }
        writing = Task { [repository, run] in
            do {
                guard try await Self.isMissing(in: repository, running: run) else { return }
                guard await Self.waitForOtherGit(in: repository) else {
                    Self.log.info("Left the commit-graph for later: another Git process kept running")
                    return
                }
                let started = ContinuousClock.now
                let result = try await run(Self.writeCommand)
                let elapsed = ContinuousClock.now - started
                Self.log.info("Wrote a commit-graph in \(elapsed, privacy: .public), exit \(result.status, privacy: .public)")
            } catch {
                // A cache the app can do without, and the Activity window shows what went wrong.
                Self.log.error("Writing a commit-graph failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    /// A single file, or a chain of layers once one has been written with `--split`.
    private static func isMissing(
        in repository: Repository,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> Bool {
        let result = try await run(folderCommand)
        guard result.status == 0,
              let path = String(bytes: result.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .newlines),
              !path.isEmpty
        else { return false }
        let folder = URL(filePath: path, directoryHint: .isDirectory, relativeTo: repository.workTree)
        return !FileManager.default.fileExists(atPath: folder.appending(path: "commit-graph").path)
            && !FileManager.default.fileExists(atPath: folder.appending(path: "commit-graphs/commit-graph-chain").path)
    }

    /// Writing the file takes a lock, which a `git gc` or other command the user started could be
    /// waiting on or holding. The app's own reads don't count.
    @concurrent
    private static func waitForOtherGit(in repository: Repository) async -> Bool {
        let deadline = ContinuousClock.now + longestWait
        let folders = [repository.workTree, repository.gitDirectory]
        while !GitProcessFinder.processes(workingIn: folders, excludingChildrenOf: getpid()).isEmpty {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: busyWait)
        }
        return true
    }
}
