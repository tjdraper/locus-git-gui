import Foundation

/// An untracked file's changes, read from the file itself, since Git has no diff for a file it
/// doesn't track. Shown the way `git diff` shows a new file: every line added.
nonisolated struct UntrackedFile: Sendable {
    /// Git takes a file with a NUL byte in its first 8,000 bytes as binary.
    private static let binaryCheckLength = 8000

    let url: URL
    let path: String

    init(path: String, in workTree: URL) {
        self.path = path
        url = workTree.appending(path: path)
    }

    /// Reads no more than the limits allow, and nothing once `keptLines` has reached their total,
    /// which is shared with the files read before this one.
    func read(limits: PatchParser.Limits, keptLines: inout Int) -> DiffFile {
        var changed = ChangedFile(change: .added, path: path, originalPath: nil)
        var patch = FilePatch(fileLine: "diff --git a/\(path) b/\(path)")
        // `git status` lists a repository inside the working tree as a folder of its own.
        guard !path.hasSuffix("/") else {
            changed.newMode = ChangedFile.submoduleMode
            return DiffFile(changed: changed, patch: patch, group: WorkingAreaGroup.untracked.rawValue)
        }
        // Not even opened, so tens of thousands of untracked files cost no more than the first few.
        guard keptLines < limits.totalLines, let (mode, contents) = try? load() else {
            patch.content = .notRead
            return DiffFile(changed: changed, patch: patch, group: WorkingAreaGroup.untracked.rawValue)
        }
        changed.newMode = mode
        if Self.isBinary(contents) {
            patch.isBinary = true
        } else {
            let lines = Self.lineCount(contents)
            patch.added = lines
            if lines > limits.fileLines || contents.count > limits.fileBytes {
                patch.content = .tooLarge
            } else {
                patch.hunks = hunks(of: contents)
                keptLines += lines
            }
        }
        return DiffFile(changed: changed, patch: patch, group: WorkingAreaGroup.untracked.rawValue)
    }

    /// The file as a patch that adds it, for `PartialPatch` to stage some of its lines.
    func rawPatch() throws -> RawFilePatch {
        let (mode, contents) = try load()
        let header = ["diff --git a/\(path) b/\(path)", "new file mode \(mode)", "--- /dev/null", "+++ b/\(path)"]
        return RawFilePatch(newFile: contents, header: header.map { Data($0.utf8) })
    }

    /// A symbolic link's contents are where it points, as Git stores it. A large file is mapped
    /// rather than read, so counting its lines doesn't hold it all in memory.
    private func load() throws -> (mode: String, contents: Data) {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            let destination = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            return (ChangedFile.linkMode, Data(destination.utf8))
        }
        let isExecutable = FileManager.default.isExecutableFile(atPath: url.path)
        return (isExecutable ? "100755" : "100644", try Data(contentsOf: url, options: .alwaysMapped))
    }

    private func hunks(of contents: Data) -> [DiffHunk] {
        let raw = RawFilePatch(newFile: contents, header: [])
        return raw.hunks.map { rawHunk in
            var hunk = DiffHunk(oldStart: rawHunk.oldStart, newStart: rawHunk.newStart, section: "")
            hunk.lines = rawHunk.lines.enumerated().map { index, line in
                var text = line.text[...]
                if text.last == UInt8(ascii: "\r") {
                    text = text.dropLast()
                }
                // swiftlint:disable:next optional_data_string_conversion
                var shown = DiffLine(kind: .added, text: String(decoding: text, as: UTF8.self), oldNumber: nil, newNumber: index + 1)
                shown.hasNoNewlineAtEnd = line.hasNoNewlineAtEnd
                return shown
            }
            return hunk
        }
    }

    static func isBinary(_ contents: Data) -> Bool {
        contents.prefix(binaryCheckLength).contains(0)
    }

    /// Counted with memchr, since a large file can be hundreds of megabytes. A last line without a
    /// newline still counts.
    static func lineCount(_ contents: Data) -> Int {
        contents.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return 0 }
            var count = 0
            var offset = 0
            while offset < buffer.count, let match = memchr(base + offset, 0x0A, buffer.count - offset) {
                count += 1
                offset = base.distance(to: UnsafeRawPointer(match)) + 1
            }
            return count + (offset < buffer.count ? 1 : 0)
        }
    }
}
