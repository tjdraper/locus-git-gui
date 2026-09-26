/// Reads a history a page at a time. Each page is its own `git log` that skips the commits already
/// read, so a repository with a million commits costs no more to open than one with ten.
nonisolated enum HistoryReader {
    static func command(for scope: HistoryScope, search: HistorySearch?, skip: Int, count: Int) -> GitCommand {
        Commit.logCommand(
            ["--topo-order", "--skip=\(skip)", "--max-count=\(count)"]
                + (search?.logArguments ?? [])
                + ["--end-of-options"] + scope.tips + ["--"]
        )
    }

    /// A history with nothing to start from, such as a repository with no commits yet, is empty
    /// rather than the checked-out branch, which is what `git log` shows given no commits.
    static func read(
        _ scope: HistoryScope,
        search: HistorySearch?,
        skip: Int,
        count: Int,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> [Commit] {
        guard !scope.tips.isEmpty else { return [] }
        return try await GitReadFailure.read(
            "history",
            with: command(for: scope, search: search, skip: skip, count: count),
            running: run,
            parse: Commit.parseLog
        )
    }

    static func hashCommand(_ candidate: String) -> GitCommand {
        Commit.logCommand(["--max-count=1", "--end-of-options", candidate + "^{commit}", "--"])
    }

    /// The commit a typed hash names, or nil when it names none, or more than one. Git fails the
    /// same way for all three, so a failure here is no match rather than a problem to report.
    static func readHashMatch(
        _ candidate: String,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> Commit? {
        let result = try await run(hashCommand(candidate))
        guard result.status == 0 else { return nil }
        return try? Commit.parseLog(result.standardOutput).first
    }
}
