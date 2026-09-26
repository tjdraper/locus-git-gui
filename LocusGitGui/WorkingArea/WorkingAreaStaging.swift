import Foundation

/// The Git commands that stage, unstage and discard changes and make commits. Paths are always
/// taken literally, so a file named `*.txt` is that file and not a pattern.
nonisolated enum WorkingAreaStaging {
    typealias Run = (GitCommand) async throws -> ChildProcess.Result

    /// A command that exited with an error, with what the user needs to see why.
    struct Failure: Error, Equatable {
        let command: GitCommand
        let result: ChildProcess.Result
    }

    /// Past this many, paths go to Git in a file rather than on the command line, which has a limit.
    static let longestPathList = 200

    static func stage(_ paths: [String], running run: Run) async throws {
        try await runWithPaths(["add"], paths, running: run)
    }

    /// Git matches every name given to `git add` against every file, which for tens of thousands of
    /// untracked files takes many seconds. `update-index` takes a long list in a moment.
    static func stageUntracked(_ paths: [String], running run: Run) async throws {
        guard paths.count > longestPathList else {
            try await stage(paths, running: run)
            return
        }
        // A repository inside the working tree is listed as a folder, which Git adds without the slash.
        let names = paths.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        let list = Data(names.joined(separator: "\0").utf8) + Data([0])
        try await perform(.changing(["update-index", "--add", "-z", "--stdin"], input: list), running: run)
    }

    /// Works before the first commit too, which `git restore --staged` doesn't.
    static func unstage(_ paths: [String], running run: Run) async throws {
        try await runWithPaths(["reset", "--quiet"], paths, running: run)
    }

    /// Changes to tracked files, leaving untracked files as they are. Conflicted files are left out,
    /// since staging one marks it resolved.
    static func stageTracked(excluding conflicts: [String], running run: Run) async throws {
        try await perform(.changing(["add", "--update", "--", ":/"] + excluding(conflicts)), running: run)
    }

    /// Every change and untracked file, other than conflicts.
    static func stageAll(excluding conflicts: [String], running run: Run) async throws {
        try await perform(.changing(["add", "--all", "--", ":/"] + excluding(conflicts)), running: run)
    }

    /// With the whole tree as its path, which a plain `git reset` would also take as leave to forget
    /// a merge or cherry-pick in progress.
    static func unstageAll(running run: Run) async throws {
        try await perform(.changing(["reset", "--quiet", "--", ":/"]), running: run)
    }

    private static func excluding(_ paths: [String]) -> [String] {
        paths.map { ":(exclude,literal)" + $0 }
    }

    /// Puts the files back as they're staged, or as they were committed if nothing is staged.
    static func discard(_ paths: [String], running run: Run) async throws {
        try await runWithPaths(["restore", "--worktree"], paths, running: run)
    }

    /// `toIndex` applies it to what's staged rather than to the files. Git recounts each hunk's
    /// lines, since `PartialPatch` leaves some out. With no unchanged lines around each change, Git
    /// has to be told not to expect them.
    static func apply(_ patch: Data, toIndex: Bool, reverse: Bool, contextLines: Int, running run: Run) async throws {
        let file = try TemporaryFile(contents: patch, suffix: ".patch")
        defer { file.remove() }
        let arguments = ["apply"] + (toIndex ? ["--cached"] : []) + (reverse ? ["--reverse"] : [])
            + ["--recount", "--whitespace=nowarn"] + (contextLines == 0 ? ["--unidiff-zero"] : []) + [file.url.path]
        try await perform(.changing(arguments), running: run)
    }

    static func commit(_ message: String, amend: Bool, running run: Run) async throws {
        try await perform(.changing(["commit", "--message=" + message] + (amend ? ["--amend"] : [])), running: run)
    }

    private static func runWithPaths(_ arguments: [String], _ paths: [String], running run: Run) async throws {
        guard paths.count > longestPathList else {
            try await perform(.changing(["--literal-pathspecs"] + arguments + ["--"] + paths), running: run)
            return
        }
        let list = try TemporaryFile(contents: Data(paths.joined(separator: "\0").utf8), suffix: ".paths")
        defer { list.remove() }
        let fromFile = ["--pathspec-from-file=\(list.url.path)", "--pathspec-file-nul"]
        try await perform(.changing(["--literal-pathspecs"] + arguments + fromFile), running: run)
    }

    private static func perform(_ command: GitCommand, running run: Run) async throws {
        let result = try await run(command)
        guard result.status == 0 else {
            throw Failure(command: command, result: result)
        }
    }
}

/// A file in the temporary folder, for Git to read something too long or too exact for the
/// command line.
nonisolated struct TemporaryFile {
    let url: URL

    init(contents: Data, suffix: String) throws {
        url = FileManager.default.temporaryDirectory.appending(path: "LocusGitGui-\(UUID().uuidString)\(suffix)")
        try contents.write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
