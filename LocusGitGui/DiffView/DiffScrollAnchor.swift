import Foundation

/// A place in a diff that survives its rows being built again: a row, and how far down that row the
/// top of the view is. Collapsing a file or going side by side changes which rows there are, so
/// it's found again by its file and its place in the file.
nonisolated struct DiffScrollAnchor: Equatable, Sendable {
    let file: DiffFile.Identity
    let block: DiffDocument.Block
    let offset: Double

    init?(top: Double, document: DiffDocument, layout: DiffLayout, files: [DiffFile]) {
        guard let block = layout.block(atY: top), files.indices.contains(document.blocks[block].file) else { return nil }
        file = files[document.blocks[block].file].id
        self.block = document.blocks[block]
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
        for index in start ..< end where Self.position(of: document.blocks[index]) <= Self.position(of: block) {
            target = index
        }
        let frame = layout.frame(of: target)
        return frame.minY + min(offset, frame.maxY - frame.minY)
    }

    /// Orders a file's rows the same way in every style: by hunk, then by line.
    private static func position(of block: DiffDocument.Block) -> (Int, Int) {
        switch block {
        case .group, .gap: (-2, 0)
        case .header: (-1, 0)
        case .notice, .images: (-1, 1)
        case let .hunk(_, hunk): (hunk, -1)
        case let .lines(_, hunk, left, right): (hunk, left ?? right ?? 0)
        }
    }
}
