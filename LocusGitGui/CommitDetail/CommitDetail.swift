import Foundation

/// What the detail column shows about a commit beyond its row in the history: the rest of its
/// message, and what it changed.
nonisolated struct CommitDetail: Equatable, Sendable {
    /// Runs a command that writes a patch, and reads the patch as it arrives.
    typealias PatchRun = (GitCommand, PatchParser.Limits) async throws -> (result: ChildProcess.Result, files: [FilePatch])

    /// Nil when the message is only a subject.
    let body: String?
    let files: [DiffFile]

    /// A merge shows what it brought into its first parent, as most people read a merge. `--root`
    /// shows a root commit's files even when `log.showRoot` is off.
    private static let diffOptions = [
        "--format=", "--no-show-signature", "--find-renames", "--diff-merges=first-parent", "--root",
    ]

    static func messageCommand(_ hash: String) -> GitCommand {
        .reading(["log", "--max-count=1", "--no-show-signature", "--format=%B", "--end-of-options", hash, "--"])
    }

    static func filesCommand(_ hash: String) -> GitCommand {
        .reading(["show", "--raw", "-z", "--no-abbrev"] + diffOptions + ["--end-of-options", hash, "--"])
    }

    /// Without the settings that make a patch something other than the plain one read here: colour,
    /// an external diff tool, text conversion and other prefixes. Paths are written as they are
    /// rather than as octal escapes. `paths` limits it to those files, and needs both of a rename's
    /// paths for Git to see it as a rename.
    static func patchCommand(_ hash: String, options: DiffOptions, paths: [String] = []) -> GitCommand {
        .reading(
            ["-c", "core.quotePath=false", "show", "--patch", "--no-color", "--no-ext-diff", "--no-textconv"]
                + ["--src-prefix=a/", "--dst-prefix=b/"] + options.arguments + diffOptions
                + ["--end-of-options", hash, "--"] + paths.map { ":(literal)" + $0 }
        )
    }

    static func read(
        _ hash: String,
        options: DiffOptions,
        running run: (GitCommand) async throws -> ChildProcess.Result,
        readingPatch readPatch: PatchRun
    ) async throws -> CommitDetail {
        let message = try await GitReadFailure.read("commit message", with: messageCommand(hash), running: run) { output in
            try UnreadableGitOutput.text(output)
        }
        let changed = try await GitReadFailure.read("changed files", with: filesCommand(hash), running: run, parse: ChangedFile.parseRaw)
        let command = patchCommand(hash, options: options)
        let (result, patches) = try await readPatch(command, .allFiles)
        guard result.status == 0 else {
            throw GitReadFailure(subject: "changes", command: command, result: result, outputWasUnreadable: false)
        }
        return CommitDetail(body: body(of: message), files: await combine(changed, patches))
    }

    /// One file's changes whatever their size, for a file whose changes were left out.
    static func readFile(
        _ file: ChangedFile,
        of hash: String,
        options: DiffOptions,
        readingPatch readPatch: PatchRun
    ) async throws -> DiffFile {
        let command = patchCommand(hash, options: options, paths: [file.originalPath, file.path].compactMap(\.self))
        let (result, patches) = try await readPatch(command, .oneFile)
        guard result.status == 0 else {
            throw GitReadFailure(subject: "changes", command: command, result: result, outputWasUnreadable: false)
        }
        return await combine([file], patches)[0]
    }

    /// `--raw` and `--patch` list files in the same order, but a file can be missing from the patch,
    /// so each is matched by the name on its `diff --git` line. A name Git had to quote falls back to
    /// the file in the same place.
    @concurrent
    private static func combine(_ changed: [ChangedFile], _ patches: [FilePatch]) async -> [DiffFile] {
        var byFileLine: [String: Int] = [:]
        for (index, patch) in patches.enumerated() {
            byFileLine[patch.fileLine] = index
        }
        var claimed = Set(changed.compactMap { byFileLine[fileLine(of: $0)] })
        return changed.enumerated().map { index, file in
            var patchIndex = byFileLine[fileLine(of: file)]
            if patchIndex == nil, patches.indices.contains(index), !claimed.contains(index) {
                patchIndex = index
                claimed.insert(index)
            }
            return DiffFile(changed: file, patch: patchIndex.map { patches[$0] } ?? FilePatch())
        }
    }

    private static func fileLine(of file: ChangedFile) -> String {
        "diff --git a/\(file.originalPath ?? file.path) b/\(file.path)"
    }

    /// Everything after the subject, which is the message's first paragraph.
    static func body(of message: String) -> String? {
        let message = message.replacingOccurrences(of: "\r\n", with: "\n")
        guard let blankLine = message.range(of: "\n\n") else { return nil }
        let body = message[blankLine.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
}
