import Foundation

/// What the detail column shows about a commit beyond its row in the history: the rest of its
/// message, and what it changed.
nonisolated struct CommitDetail: Equatable, Sendable {
    /// Nil when the message is only a subject.
    let body: String?
    let files: [ChangedFile]
    let patch: CommitPatch

    /// A merge shows what it brought into its first parent, as most people read a merge. `--root`
    /// shows a root commit's files even when `log.showRoot` is off.
    private static let diffOptions = [
        "--format=", "--no-show-signature", "--find-renames", "--diff-merges=first-parent", "--root",
    ]

    static func messageCommand(_ hash: String) -> GitCommand {
        .reading(["log", "--max-count=1", "--no-show-signature", "--format=%B", "--end-of-options", hash, "--"])
    }

    static func filesCommand(_ hash: String) -> GitCommand {
        .reading(["show", "--name-status", "-z"] + diffOptions + ["--end-of-options", hash, "--"])
    }

    /// Without the settings that make a patch something other than the plain one read here: colour,
    /// an external diff tool, text conversion and other prefixes. Paths are written as they are
    /// rather than as octal escapes.
    static func patchCommand(_ hash: String) -> GitCommand {
        .reading(
            ["-c", "core.quotePath=false", "show", "--patch", "--no-color", "--no-ext-diff", "--no-textconv"]
                + ["--src-prefix=a/", "--dst-prefix=b/"] + diffOptions + ["--end-of-options", hash, "--"]
        )
    }

    static func read(_ hash: String, running run: (GitCommand) async throws -> ChildProcess.Result) async throws -> CommitDetail {
        let message = try await GitReadFailure.read("commit message", with: messageCommand(hash), running: run) { output in
            try UnreadableGitOutput.text(output)
        }
        let files = try await GitReadFailure.read("changed files", with: filesCommand(hash), running: run, parse: ChangedFile.parseList)
        let patch = try await GitReadFailure.read("changes", with: patchCommand(hash), running: run) { output in
            CommitPatch(parsing: output)
        }
        return CommitDetail(body: body(of: message), files: files, patch: patch)
    }

    /// Everything after the subject, which is the message's first paragraph.
    static func body(of message: String) -> String? {
        let message = message.replacingOccurrences(of: "\r\n", with: "\n")
        guard let blankLine = message.range(of: "\n\n") else { return nil }
        let body = message[blankLine.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
}
