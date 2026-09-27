import Foundation

/// A place in a diff that survives its rows being built again: a row, and how far down that row the
/// top of the view is. Collapsing a file or going side by side changes which rows there are, so
/// it's found again by its file and its place in the file. Saved with a diff's place, so it holds
/// only what outlasts the diff being read again.
nonisolated struct DiffScrollAnchor: Codable, Equatable, Sendable {
    /// A row's place in its file, by hunk and then by line, which is the same in every style.
    struct Position: Codable, Comparable, Sendable {
        let hunk: Int
        let line: Int

        static func < (lhs: Position, rhs: Position) -> Bool {
            (lhs.hunk, lhs.line) < (rhs.hunk, rhs.line)
        }
    }

    let file: DiffFile.Identity
    let position: Position
    let offset: Double

    init(file: DiffFile.Identity, position: Position, offset: Double) {
        self.file = file
        self.position = position
        self.offset = offset
    }

    init?(top: Double, document: DiffDocument, layout: DiffLayout, files: [DiffFile]) {
        guard let block = layout.block(atY: top), files.indices.contains(document.blocks[block].file) else { return nil }
        file = files[document.blocks[block].file].id
        position = Self.position(of: document.blocks[block])
        offset = top - layout.top(of: block)
    }

    /// Where the view's top goes now: the same row, or the last one before where it was.
    func top(in document: DiffDocument, layout: DiffLayout, files: [DiffFile]) -> Double? {
        guard let index = files.firstIndex(where: { $0.id == file }) else { return nil }
        let header = document.fileStarts[index]
        // The group heading or space above the file.
        let isAbove = header > 0 && [.group(file: index), .gap(file: index)].contains(document.blocks[header - 1])
        let start = isAbove ? header - 1 : header
        let end = document.fileEnds[index]
        var target = header
        for index in start ..< end where Self.position(of: document.blocks[index]) <= position {
            target = index
        }
        let frame = layout.frame(of: target)
        return frame.minY + min(offset, frame.maxY - frame.minY)
    }

    private static func position(of block: DiffDocument.Block) -> Position {
        switch block {
        case .group, .gap: Position(hunk: -2, line: 0)
        case .header: Position(hunk: -1, line: 0)
        case .notice, .images: Position(hunk: -1, line: 1)
        case let .hunk(_, hunk): Position(hunk: hunk, line: -1)
        case let .lines(_, hunk, left, right): Position(hunk: hunk, line: left ?? right ?? 0)
        }
    }
}
