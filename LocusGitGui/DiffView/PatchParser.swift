import Foundation

/// Reads a patch as Git writes it, a piece at a time as it arrives, into one `FilePatch` per file.
/// Lines past the limits are counted but not kept, so a commit with one enormous generated file,
/// or thousands of files, costs no more memory than one that fits.
nonisolated struct PatchParser: Sendable {
    struct Limits: Sendable {
        let fileLines: Int
        let fileBytes: Int
        let totalLines: Int

        /// For every file in a diff at once, where one file mustn't hold up the rest.
        static let allFiles = Limits(fileLines: 5000, fileBytes: 512 * 1024, totalLines: 50000)
        /// For one file the user asked to see.
        static let oneFile = Limits(fileLines: .max, fileBytes: 64 * 1024 * 1024, totalLines: .max)
    }

    let limits: Limits
    private(set) var files: [FilePatch] = []
    /// The end of the last piece, which may stop partway through a line.
    private var partial = Data()
    private var fileLine = Data()
    private var inHeader = true
    private var oldLine = 0
    private var newLine = 0
    private var keptLines = 0
    private var fileKeptLines = 0
    private var fileKeptBytes = 0

    init(limits: Limits) {
        self.limits = limits
    }

    mutating func consume(_ data: Data) {
        partial.append(data)
        var lineStart = 0
        let count = partial.count
        // Found with memchr, since a large commit's patch is hundreds of megabytes of lines.
        let newlines = partial.withUnsafeBytes { buffer -> [Int] in
            guard let base = buffer.baseAddress else { return [] }
            var found: [Int] = []
            var offset = 0
            while offset < count, let match = memchr(base + offset, 0x0A, count - offset) {
                let index = base.distance(to: UnsafeRawPointer(match))
                found.append(index)
                offset = index + 1
            }
            return found
        }
        for newline in newlines {
            handle(partial[partial.startIndex + lineStart ..< partial.startIndex + newline])
            lineStart = newline + 1
        }
        partial = lineStart < count ? Data(partial[(partial.startIndex + lineStart)...]) : Data()
    }

    /// Takes the last line, which has no newline after it when the patch ends without one.
    mutating func finish() -> [FilePatch] {
        if !partial.isEmpty {
            handle(partial)
            partial = Data()
        }
        return files
    }

    private static let diffPrefix = Data("diff --git ".utf8)
    private static let hunkPrefix = Data("@@".utf8)
    private static let binaryPrefixes = [Data("Binary files ".utf8), Data("GIT binary patch".utf8)]

    /// No line of a file's changes starts with `diff`, since each starts with a space, `+`, `-`,
    /// `@` or `\`, so `diff --git` at the start of a line always begins the next file. A file whose
    /// type changed, such as one replaced by a symbolic link, is written as a deletion and an
    /// addition under the same `diff --git` line, and is kept as one file, as `--raw` lists it.
    private mutating func handle(_ line: Data) {
        if line.starts(with: Self.diffPrefix) {
            if line != fileLine || files.isEmpty {
                // swiftlint:disable:next optional_data_string_conversion
                let name = String(decoding: line, as: UTF8.self)
                files.append(FilePatch(fileLine: name, content: keptLines >= limits.totalLines ? .notRead : .shown))
                fileKeptLines = 0
                fileKeptBytes = 0
            }
            fileLine = line
            inHeader = true
            return
        }
        guard !files.isEmpty else { return }
        // A removed line whose text starts with `-- ` reads as `--- `, so the file's header is only
        // recognized before its first hunk.
        if inHeader {
            handleHeader(line)
        } else {
            handleChange(line)
        }
    }

    private mutating func handleHeader(_ line: Data) {
        if line.starts(with: Self.hunkPrefix) {
            inHeader = false
            startHunk(line)
        } else if Self.binaryPrefixes.contains(where: { line.starts(with: $0) }) {
            files[files.count - 1].isBinary = true
        }
    }

    private mutating func handleChange(_ line: Data) {
        switch line.first {
        case UInt8(ascii: "@"):
            if line.starts(with: Self.hunkPrefix) {
                startHunk(line)
            }
        case UInt8(ascii: "+"):
            add(.added, line)
        case UInt8(ascii: "-"):
            add(.removed, line)
        case UInt8(ascii: " "), nil:
            add(.context, line)
        case UInt8(ascii: "\\"):
            markNoNewlineAtEnd()
        default:
            break
        }
    }

    /// `@@ -<old start>[,<count>] +<new start>[,<count>] @@ <section>`
    private mutating func startHunk(_ line: Data) {
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: line, as: UTF8.self)
        let parts = text.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false)
        func start(_ index: Int) -> Int {
            guard parts.indices.contains(index) else { return 0 }
            return Int(parts[index].dropFirst().prefix { $0 != "," }) ?? 0
        }
        oldLine = start(1)
        newLine = start(2)
        guard files[files.count - 1].content == .shown else { return }
        let section = parts.count > 4 ? String(parts[4]) : ""
        files[files.count - 1].hunks.append(DiffHunk(oldStart: oldLine, newStart: newLine, section: section))
    }

    private mutating func add(_ kind: DiffLine.Kind, _ line: Data) {
        let index = files.count - 1
        var oldNumber: Int?
        var newNumber: Int?
        switch kind {
        case .added:
            files[index].added += 1
            newNumber = newLine
            newLine += 1
        case .removed:
            files[index].removed += 1
            oldNumber = oldLine
            oldLine += 1
        case .context:
            oldNumber = oldLine
            newNumber = newLine
            oldLine += 1
            newLine += 1
        }
        guard files[index].content == .shown, !files[index].hunks.isEmpty else { return }
        fileKeptLines += 1
        fileKeptBytes += line.count
        guard fileKeptLines <= limits.fileLines, fileKeptBytes <= limits.fileBytes else {
            keptLines -= fileKeptLines - 1
            files[index].hunks = []
            files[index].content = .tooLarge
            return
        }
        keptLines += 1
        var text = line.dropFirst()
        if text.last == UInt8(ascii: "\r") {
            text = text.dropLast()
        }
        // File contents are in whatever encoding the file uses, and a replacement character is
        // better than losing the whole diff to a failed decode.
        // swiftlint:disable:next optional_data_string_conversion
        let decoded = String(decoding: text, as: UTF8.self)
        files[index].hunks[files[index].hunks.count - 1].lines.append(
            DiffLine(kind: kind, text: decoded, oldNumber: oldNumber, newNumber: newNumber)
        )
    }

    private mutating func markNoNewlineAtEnd() {
        let index = files.count - 1
        guard let hunk = files[index].hunks.indices.last, !files[index].hunks[hunk].lines.isEmpty else { return }
        let line = files[index].hunks[hunk].lines.count - 1
        files[index].hunks[hunk].lines[line].hasNoNewlineAtEnd = true
    }
}
