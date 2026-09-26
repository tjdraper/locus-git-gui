import Foundation

/// Reads the working area's changes: the staged ones from `git diff --cached`, the unstaged ones from
/// `git diff`, and untracked files from the files themselves. The files come from `git status`,
/// which the window has already read, so each is matched with its changes by name.
nonisolated enum WorkingAreaDiff {
    /// Every group's files, in the order the working area lists them.
    static func read(
        _ status: RepositoryStatus,
        options: DiffOptions,
        workTree: URL,
        readingPatch readPatch: CommitDetail.PatchRun
    ) async throws -> [DiffFile] {
        let entries = WorkingAreaFiles.list(status)
        var files: [DiffFile] = []
        for group in WorkingAreaGroup.allCases {
            let changed = entries.filter { $0.group == group }.map(\.file)
            guard !changed.isEmpty else { continue }
            switch group {
            case .staged, .unstaged:
                let command = patchCommand(group, options: options)
                let (result, patches) = try await readPatch(command, .allFiles)
                guard result.status == 0 else {
                    throw GitReadFailure(subject: "changes", command: command, result: result, outputWasUnreadable: false)
                }
                files += await combine(changed, patches, group: group)
            case .untracked:
                files += await readUntracked(changed.map(\.path), in: workTree)
            case .conflicted:
                files += changed.map { DiffFile(changed: $0, patch: FilePatch(), group: group.rawValue) }
            }
        }
        return files
    }

    /// One file's changes whatever their size, for changes that were left out and for a file window.
    static func readFile(
        _ file: DiffFile,
        options: DiffOptions,
        workTree: URL,
        readingPatch readPatch: CommitDetail.PatchRun
    ) async throws -> DiffFile {
        guard let group = WorkingAreaGroup(file) else { return file }
        switch group {
        case .staged, .unstaged:
            let paths = [file.changed.originalPath, file.changed.path].compactMap(\.self)
            let command = patchCommand(group, options: options, paths: paths)
            let (result, patches) = try await readPatch(command, .oneFile)
            guard result.status == 0 else {
                throw GitReadFailure(subject: "changes", command: command, result: result, outputWasUnreadable: false)
            }
            return await combine([file.changed], patches, group: group)[0]
        case .untracked:
            return await readUntracked([file.changed.path], in: workTree, limits: .oneFile)[0]
        case .conflicted:
            return file
        }
    }

    /// The same patch as `patchCommand`, kept as Git wrote it, for staging part of it.
    static func readRawPatch(
        of file: DiffFile,
        options: DiffOptions,
        workTree: URL,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> RawFilePatch? {
        guard let group = WorkingAreaGroup(file) else { return nil }
        switch group {
        case .staged, .unstaged:
            let paths = [file.changed.originalPath, file.changed.path].compactMap(\.self)
            return try await GitReadFailure.read("changes", with: patchCommand(group, options: options, paths: paths), running: run) {
                RawFilePatch(parsing: $0)
            }
        case .untracked:
            return try await readUntrackedPatch(file.changed.path, in: workTree)
        case .conflicted:
            return nil
        }
    }

    @concurrent
    private static func readUntrackedPatch(_ path: String, in workTree: URL) async throws -> RawFilePatch {
        try UntrackedFile(path: path, in: workTree).rawPatch()
    }

    /// Without the settings that make a patch something other than the plain one read here, as for a
    /// commit (see `CommitDetail.patchCommand`). A submodule is shown as the commits it moved between,
    /// whatever `diff.submodule` says. `paths` limits it to those files.
    static func patchCommand(_ group: WorkingAreaGroup, options: DiffOptions, paths: [String] = []) -> GitCommand {
        .reading(
            ["-c", "core.quotePath=false", "diff"] + (group == .staged ? ["--cached"] : [])
                + ["--patch", "--no-color", "--no-ext-diff", "--no-textconv", "--submodule=short", "--find-renames"]
                + ["--src-prefix=a/", "--dst-prefix=b/"] + options.arguments
                + ["--"] + paths.map { ":(literal)" + $0 }
        )
    }

    /// By the name on each patch's `diff --git` line. A name Git had to quote falls back to the next
    /// patch no file has claimed, since both list files in the same order.
    @concurrent
    private static func combine(_ changed: [ChangedFile], _ patches: [FilePatch], group: WorkingAreaGroup) async -> [DiffFile] {
        var byFileLine: [String: Int] = [:]
        for (index, patch) in patches.enumerated() {
            byFileLine[patch.fileLine] = index
        }
        var claimed = Set(changed.compactMap { byFileLine[fileLine(of: $0)] })
        var unclaimed = patches.indices.filter { !claimed.contains($0) }.makeIterator()
        return changed.map { file in
            var index = byFileLine[fileLine(of: file)]
            if index == nil, let next = unclaimed.next() {
                index = next
                claimed.insert(next)
            }
            return DiffFile(changed: file, patch: index.map { patches[$0] } ?? FilePatch(), group: group.rawValue)
        }
    }

    private static func fileLine(of file: ChangedFile) -> String {
        "diff --git a/\(file.originalPath ?? file.path) b/\(file.path)"
    }

    /// Away from the main actor, since it reads every file.
    @concurrent
    private static func readUntracked(_ paths: [String], in workTree: URL, limits: PatchParser.Limits = .allFiles) async -> [DiffFile] {
        var keptLines = 0
        return paths.map { path in
            UntrackedFile(path: path, in: workTree).read(limits: limits, keptLines: &keptLines)
        }
    }
}
