import Foundation

/// One file's patch kept as the bytes Git wrote, so part of it can be handed back to `git apply`
/// exactly. The diff view's own `FilePatch` has decoded its text and dropped carriage returns, and a
/// patch built from that wouldn't apply to a file with Windows line endings or in another encoding.
nonisolated struct RawFilePatch: Equatable, Sendable {
    struct Hunk: Equatable, Sendable {
        let oldStart: Int
        let newStart: Int
        var lines: [Line] = []
    }

    struct Line: Equatable, Sendable {
        let kind: DiffLine.Kind
        /// Without the leading `+`, `-` or space, or the newline.
        let text: Data
        /// Followed by Git's `\ No newline at end of file`.
        var hasNoNewlineAtEnd = false
    }

    /// The lines before the first hunk, such as `new file mode 100644`.
    var header: [Data] = []
    var hunks: [Hunk] = []

    var isNewFile: Bool {
        header.contains { $0.starts(with: Data("new file mode ".utf8)) }
    }

    var isDeletedFile: Bool {
        header.contains { $0.starts(with: Data("deleted file mode ".utf8)) }
    }

    /// The first file in a patch, which should hold only one. Nil when it holds none.
    init?(parsing patch: Data) {
        var sawFile = false
        for line in patch.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            if line.starts(with: Data("diff ".utf8)) {
                guard !sawFile else { break }
                sawFile = true
                header.append(Data(line))
                continue
            }
            guard sawFile else { continue }
            if line.starts(with: Data("@@".utf8)) {
                hunks.append(Self.hunk(startingWith: line))
            } else if hunks.isEmpty {
                header.append(Data(line))
            } else {
                append(line)
            }
        }
        guard sawFile else { return nil }
    }

    /// Parsed straight from a file, as `git diff` would show it as new.
    init(newFile contents: Data, header: [Data]) {
        self.header = header
        var lines = contents.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        let endsWithNewline = lines.last?.isEmpty == true
        if endsWithNewline {
            lines.removeLast()
        }
        guard !lines.isEmpty else { return }
        var hunk = Hunk(oldStart: 0, newStart: 1)
        hunk.lines = lines.map { Line(kind: .added, text: Data($0)) }
        hunk.lines[hunk.lines.count - 1].hasNoNewlineAtEnd = !endsWithNewline
        hunks = [hunk]
    }

    /// True when these are the same changes the diff view shows, read the same way, so a hunk or
    /// line picked in the view is the one here.
    func matches(_ patch: FilePatch) -> Bool {
        guard hunks.count == patch.hunks.count else { return false }
        for (raw, shown) in zip(hunks, patch.hunks) {
            guard raw.oldStart == shown.oldStart, raw.newStart == shown.newStart, raw.lines.count == shown.lines.count else {
                return false
            }
            let differs = zip(raw.lines, shown.lines).contains { line, shownLine in
                line.kind != shownLine.kind || Self.shownText(line.text) != shownLine.text
            }
            if differs {
                return false
            }
        }
        return true
    }

    /// As `PatchParser` decodes a line for the view.
    private static func shownText(_ text: Data) -> String {
        var text = text[...]
        if text.last == UInt8(ascii: "\r") {
            text = text.dropLast()
        }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: text, as: UTF8.self)
    }

    /// `@@ -<old start>[,<count>] +<new start>[,<count>] @@`
    private static func hunk(startingWith line: Data.SubSequence) -> Hunk {
        // swiftlint:disable:next optional_data_string_conversion
        let parts = String(decoding: line, as: UTF8.self).split(separator: " ", maxSplits: 3)
        func start(_ index: Int) -> Int {
            guard parts.indices.contains(index) else { return 0 }
            return Int(parts[index].dropFirst().prefix { $0 != "," }) ?? 0
        }
        return Hunk(oldStart: start(1), newStart: start(2))
    }

    private mutating func append(_ line: Data.SubSequence) {
        let last = hunks.count - 1
        let kind: DiffLine.Kind
        switch line.first {
        case UInt8(ascii: "+"): kind = .added
        case UInt8(ascii: "-"): kind = .removed
        case UInt8(ascii: " "): kind = .context
        case UInt8(ascii: "\\"):
            if !hunks[last].lines.isEmpty {
                hunks[last].lines[hunks[last].lines.count - 1].hasNoNewlineAtEnd = true
            }
            return
        default:
            // The empty piece after the patch's final newline.
            return
        }
        hunks[last].lines.append(Line(kind: kind, text: Data(line.dropFirst())))
    }
}
