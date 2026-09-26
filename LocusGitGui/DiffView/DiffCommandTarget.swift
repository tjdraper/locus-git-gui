import Foundation

/// Which file a diff's file commands act on, from what's selected, what Next File and Previous File
/// went to, and what's in view.
nonisolated struct DiffCommandTarget: Sendable {
    let document: DiffDocument
    let layout: DiffLayout
    let selection: DiffSelection?
    /// The part of the diff in view, below the header stuck at the top.
    let visibleTop: Double
    let visibleBottom: Double
    /// The file Next File or Previous File went to, which can't always be scrolled to the top, such
    /// as when every file fits in view.
    var markedFile: Int?

    struct Hunk: Equatable, Sendable {
        let file: Int
        let hunk: Int
    }

    /// The file with the selection in it while that's in view, then the one Next File or Previous
    /// File went to while that's in view, and otherwise the one at the top.
    var file: Int? {
        if let block = selectedBlockInView {
            return document.file(at: block)
        }
        if let markedFile, isInView(file: markedFile) {
            return markedFile
        }
        return layout.block(atY: visibleTop).flatMap(document.file(at:)) ?? document.blocks.last?.file
    }

    /// Any of it, its header included. The header stuck at the top covers the view down to
    /// `visibleTop`.
    func isInView(file: Int) -> Bool {
        guard document.fileStarts.indices.contains(file) else { return false }
        let start = layout.top(of: document.fileStarts[file])
        let end = layout.top(of: document.fileEnds[file])
        return end > visibleTop - layout.metrics.headerHeight && start < visibleBottom
    }

    /// The hunk with the selection in it while that's in view, and otherwise the current file's
    /// first hunk from the top of the view down.
    var hunk: Hunk? {
        if let block = selectedBlockInView, let hunk = Self.hunk(of: document.blocks[block]) {
            return hunk
        }
        guard let file else { return nil }
        let top = layout.block(atY: visibleTop) ?? document.fileStarts[file]
        let blocks = max(top, document.fileStarts[file]) ..< document.fileEnds[file]
        return blocks.lazy.compactMap { Self.hunk(of: document.blocks[$0]) }.first
    }

    private var selectedBlockInView: Int? {
        guard let selection, document.blocks.indices.contains(selection.head.block) else { return nil }
        let frame = layout.frame(of: selection.head.block)
        return frame.maxY > visibleTop && frame.minY < visibleBottom ? selection.head.block : nil
    }

    private static func hunk(of block: DiffDocument.Block) -> Hunk? {
        switch block {
        case let .hunk(file, hunk), let .lines(file, hunk, _, _): Hunk(file: file, hunk: hunk)
        default: nil
        }
    }

    /// When the marked file is refreshed away, such as once Space has staged it, the next file that
    /// was after it takes the mark, so the keyboard moves on through the files.
    static func markedFile(
        _ marked: DiffFile.Identity?,
        from previous: [DiffFile],
        in files: [DiffFile]
    ) -> DiffFile.Identity? {
        guard let marked else { return nil }
        let shown = Set(files.map(\.id))
        guard !shown.contains(marked) else { return marked }
        guard let index = previous.firstIndex(where: { $0.id == marked }) else { return nil }
        let after = previous[(index + 1)...].first { shown.contains($0.id) }
        return (after ?? previous[..<index].last { shown.contains($0.id) })?.id
    }
}
