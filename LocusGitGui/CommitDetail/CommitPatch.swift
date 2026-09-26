import Foundation

/// A commit's changes as `git show --patch` prints them, split into one section per file and each
/// line sorted by what it is, so it can be shown without Git's colours.
nonisolated struct CommitPatch: Equatable, Sendable {
    /// Past this, the rest of a commit's changes are left out, so one enormous commit can't stall
    /// the window.
    static let displayLimit = 2 * 1024 * 1024

    /// One per file, in the order `--name-status` lists them.
    let files: [[CommitPatchLine]]
    let isShortened: Bool

    /// Header lines Git always writes and the file's own header already says.
    private static let redundantHeaderPrefixes = ["diff --git ", "index ", "--- ", "+++ "]

    init(files: [[CommitPatchLine]], isShortened: Bool) {
        self.files = files
        self.isShortened = isShortened
    }

    /// No line of a file's changes starts with `diff`, since every one starts with a space, `+`,
    /// `-`, `@` or `\`, so `diff --git` at the start of a line always begins the next file. A file
    /// whose type changed, such as one replaced by a symbolic link, is written as a deletion and
    /// an addition under the same `diff --git` line, and is kept as one file, as `--name-status`
    /// lists it.
    init(parsing output: Data) {
        let isShortened = output.count > Self.displayLimit
        var shown = output.prefix(Self.displayLimit)
        if isShortened, let lastNewline = shown.lastIndex(of: UInt8(ascii: "\n")) {
            shown = shown[..<lastNewline]
        }
        if shown.last == UInt8(ascii: "\n") {
            shown = shown.dropLast()
        }
        var files: [[CommitPatchLine]] = []
        var inHeader = true
        var fileLine: String?
        // Split as bytes, since as text a CRLF line ending is one character that isn't a newline.
        for bytes in shown.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) where !shown.isEmpty {
            // File contents are in whatever encoding the file uses, and a replacement character is
            // better than losing the whole diff to a failed decode.
            // swiftlint:disable:next optional_data_string_conversion
            var line = String(decoding: bytes, as: UTF8.self)
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            if line.hasPrefix("diff --git ") {
                if line != fileLine || files.isEmpty {
                    files.append([])
                }
                fileLine = line
                inHeader = true
            } else if files.isEmpty {
                files.append([])
            }
            if line.hasPrefix("@@") {
                inHeader = false
            }
            guard let classified = Self.classify(line, inHeader: inHeader) else { continue }
            files[files.count - 1].append(classified)
        }
        self.init(files: files, isShortened: isShortened)
    }

    /// A removed line whose text starts with `-- ` reads as `--- `, so the file header is only
    /// recognized before the first hunk.
    private static func classify(_ line: String, inHeader: Bool) -> CommitPatchLine? {
        if inHeader {
            if redundantHeaderPrefixes.contains(where: { line.hasPrefix($0) }) {
                return nil
            }
            return CommitPatchLine(kind: .fileInfo, text: line)
        }
        let kind: CommitPatchLine.Kind = switch line.unicodeScalars.first {
        case "@": .hunkHeader
        case "+": .added
        case "-": .removed
        case "\\": .note
        default: .context
        }
        return CommitPatchLine(kind: kind, text: line)
    }
}

/// One line of a file's changes.
nonisolated struct CommitPatchLine: Equatable, Sendable {
    enum Kind: Sendable {
        /// About the file rather than its contents, such as a rename or a mode change.
        case fileInfo
        case hunkHeader
        case added
        case removed
        case context
        /// Git's `\ No newline at end of file`.
        case note
    }

    let kind: Kind
    let text: String
}
