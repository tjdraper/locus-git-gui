import Foundation

/// One file's changes, read from a patch.
nonisolated struct FilePatch: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case shown
        /// Left out because the file's changes alone are past the limit. `hunks` is empty.
        case tooLarge
        /// Left out because the changes before it already reached the limit. `hunks` is empty.
        case notRead
    }

    /// Git's `diff --git a/<path> b/<path>` line, which names the file the patch is for.
    var fileLine = ""
    var hunks: [DiffHunk] = []
    /// Counted for every file, including those whose changes were left out.
    var added = 0
    var removed = 0
    var isBinary = false
    var content = Content.shown

    var changedLines: Int {
        added + removed
    }
}

/// A run of changed lines and the unchanged lines around them.
nonisolated struct DiffHunk: Equatable, Sendable {
    let oldStart: Int
    let newStart: Int
    /// What Git found the hunk to be inside, such as a function's first line. Empty when it found
    /// nothing.
    let section: String
    var lines: [DiffLine] = []
}

nonisolated struct DiffLine: Equatable, Sendable {
    enum Kind: Sendable {
        case context
        case added
        case removed
    }

    let kind: Kind
    /// Without the leading `+`, `-` or space, or a trailing carriage return.
    let text: String
    let oldNumber: Int?
    let newNumber: Int?
    /// How wide the text is on one line, kept so that working out which lines wrap only has to
    /// look at the long ones.
    let columns: Int
    /// In UTF-16 units.
    let length: Int
    /// Git's `\ No newline at end of file`, which follows the line it's about.
    var hasNoNewlineAtEnd = false
    /// UTF-16 ranges of the text that differ from the line this one replaced, or that replaced it.
    var changedWords: [Range<Int>] = []

    init(kind: Kind, text: String, oldNumber: Int?, newNumber: Int?) {
        self.kind = kind
        self.text = text
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        length = text.utf16.count
        columns = length > LineWrap.longLine ? length : LineWrap.width(of: text.utf16)
    }
}
