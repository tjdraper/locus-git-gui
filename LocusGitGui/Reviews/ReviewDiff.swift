import Foundation

/// Reads what a review compares: the files that differ between its two points with their contents
/// on each side, and one file's changes at a time.
nonisolated enum ReviewDiff {
    typealias Run = (GitCommand) async throws -> ChildProcess.Result

    /// The files that differ, and which of them Git doesn't track yet.
    struct Listing: Equatable, Sendable {
        var files: [ChangedFile] = []
        var untracked: Set<String> = []
    }

    /// `head` is nil for the working tree.
    static func filesCommand(from base: String, to head: String?) -> GitCommand {
        .reading(["diff", "--raw", "-z", "--no-abbrev", "--find-renames", "--end-of-options", base] + [head].compactMap(\.self) + ["--"])
    }

    static let untrackedCommand = GitCommand.reading(["ls-files", "--others", "--exclude-standard", "-z"])

    /// Without `-w`, so reading a review writes nothing.
    static func hashCommand(_ paths: [String]) -> GitCommand {
        var command = GitCommand.reading(["hash-object", "--stdin-paths"])
        command.input = Data(paths.map { $0 + "\n" }.joined().utf8)
        return command
    }

    /// Writes the file's contents into the repository, so a check or comment on a file in the
    /// working tree can be compared with how it is later.
    static func storeCommand(_ path: String) -> GitCommand {
        .changing(["hash-object", "-w", "--", path])
    }

    /// Git reads a link's target from the input, the way it stores a link.
    static func linkHashCommand(target: String) -> GitCommand {
        var command = GitCommand.reading(["hash-object", "--stdin"])
        command.input = Data(target.utf8)
        return command
    }

    /// Like `CommitDetail.patchCommand`, plain whatever the user's diff settings.
    static func patchCommand(from base: String, to head: String?, options: DiffOptions, paths: [String]) -> GitCommand {
        .reading(
            ["-c", "core.quotePath=false", "diff", "--patch", "--no-color", "--no-ext-diff", "--no-textconv", "--submodule=short"]
                + ["--find-renames", "--src-prefix=a/", "--dst-prefix=b/"] + options.arguments
                + ["--end-of-options", base] + [head].compactMap(\.self) + ["--"] + paths.map { ":(literal)" + $0 }
        )
    }

    /// Two versions of one file, compared by their contents alone.
    static func objectsPatchCommand(from old: String, to new: String, options: DiffOptions) -> GitCommand {
        .reading(
            ["-c", "core.quotePath=false", "diff", "--patch", "--no-color", "--no-ext-diff", "--no-textconv"]
                + ["--src-prefix=a/", "--dst-prefix=b/"] + options.arguments + ["--end-of-options", old, new]
        )
    }

    static func readFiles(from base: String, to head: String?, workTree: URL, running run: Run) async throws -> Listing {
        var files = try await GitReadFailure.readConcurrently(
            "review’s files",
            with: filesCommand(from: base, to: head),
            running: run,
            parse: ChangedFile.parseRaw
        )
        guard head == nil else {
            return Listing(files: files)
        }
        let untrackedPaths = try await GitReadFailure.read("untracked files", with: untrackedCommand, running: run) { output in
            try output.split(separator: 0).map(UnreadableGitOutput.text)
        }
        files += untrackedPaths.map { untrackedFile($0, in: workTree) }
        files = try await hashingWorkingTree(files, in: workTree, running: run)
        files.sort { $0.path < $1.path }
        return Listing(files: files, untracked: Set(untrackedPaths))
    }

    /// `git diff` names a file in the working tree without its contents unless it matches the
    /// index, so those are hashed here. A folder `ls-files` lists is a repository of its own.
    private static func hashingWorkingTree(_ files: [ChangedFile], in workTree: URL, running run: Run) async throws -> [ChangedFile] {
        let needsHash = files.indices.filter { index in
            let file = files[index]
            return file.newObject == nil && file.newMode != ChangedFile.absentMode && file.newMode != ChangedFile.submoduleMode
        }
        var hashed = files
        let links = needsHash.filter { files[$0].newMode == ChangedFile.linkMode }
        for index in links {
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: workTree.appending(path: files[index].path).path)
            hashed[index].newObject = try await GitReadFailure.read("link", with: linkHashCommand(target: target), running: run) {
                try UnreadableGitOutput.text($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let regular = needsHash.filter { files[$0].newMode != ChangedFile.linkMode }
        guard !regular.isEmpty else { return hashed }
        let hashes = try await GitReadFailure.read(
            "working tree’s files",
            with: hashCommand(regular.map { files[$0].path }),
            running: run
        ) { output in
            try UnreadableGitOutput.text(output).split(separator: "\n").map(String.init)
        }
        guard hashes.count == regular.count else {
            throw UnreadableGitOutput(reason: "Hashed a different number of files than asked")
        }
        for (index, hash) in zip(regular, hashes) {
            hashed[index].newObject = hash
        }
        return hashed
    }

    private static func untrackedFile(_ path: String, in workTree: URL) -> ChangedFile {
        var file = ChangedFile(change: .added, path: path, originalPath: nil)
        if path.hasSuffix("/") {
            file.newMode = ChangedFile.submoduleMode
            return file
        }
        let url = workTree.appending(path: path)
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            file.newMode = ChangedFile.linkMode
        } else {
            file.newMode = FileManager.default.isExecutableFile(atPath: url.path) ? "100755" : "100644"
        }
        return file
    }

    /// What reading one file's changes needs besides the file.
    struct Source: Sendable {
        let revision: ReviewRevision
        let options: DiffOptions
        let workTree: URL
    }

    /// One file's changes. An untracked file is read from the file itself, as the working area
    /// reads it, since `git diff` leaves untracked files out.
    static func readFile(
        _ file: ChangedFile,
        isUntracked: Bool,
        from source: Source,
        limits: PatchParser.Limits,
        readingPatch readPatch: CommitDetail.PatchRun
    ) async throws -> DiffFile {
        if isUntracked {
            return await readUntracked(file, in: source.workTree, limits: limits)
        }
        let command = patchCommand(
            from: source.revision.comparedBase,
            to: source.revision.comparedHead,
            options: source.options,
            paths: [file.originalPath, file.path].compactMap(\.self)
        )
        return try await read(file, with: command, limits: limits, readingPatch: readPatch)
    }

    /// Only what changed in a file since it was reviewed: its contents then against its contents
    /// now, both objects in the repository.
    static func readChangesSince(
        _ versions: (reviewed: String, current: String),
        in file: ChangedFile,
        options: DiffOptions,
        limits: PatchParser.Limits,
        readingPatch readPatch: CommitDetail.PatchRun
    ) async throws -> DiffFile {
        let command = objectsPatchCommand(from: versions.reviewed, to: versions.current, options: options)
        return try await read(file, with: command, limits: limits, readingPatch: readPatch)
    }

    private static func read(
        _ file: ChangedFile,
        with command: GitCommand,
        limits: PatchParser.Limits,
        readingPatch readPatch: CommitDetail.PatchRun
    ) async throws -> DiffFile {
        let (result, patches) = try await readPatch(command, limits)
        guard result.status == 0 else {
            throw GitReadFailure(subject: "changes", command: command, result: result, outputWasUnreadable: false)
        }
        return DiffFile(changed: file, patch: patches.first ?? FilePatch())
    }

    @concurrent
    private static func readUntracked(_ file: ChangedFile, in workTree: URL, limits: PatchParser.Limits) async -> DiffFile {
        var keptLines = 0
        let read = UntrackedFile(path: file.path, in: workTree).read(limits: limits, keptLines: &keptLines)
        return DiffFile(changed: file, patch: read.patch)
    }
}
