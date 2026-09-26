import Foundation

/// A diff as the rows it's shown in, top to bottom: each file's header, anything to say about the
/// file, and its hunks and lines. Built again when a file is collapsed or expanded, or the view
/// changes between inline and side by side.
nonisolated struct DiffDocument: Equatable, Sendable {
    enum Style: Sendable {
        /// Removed lines above the added lines that replaced them, with both line numbers.
        case inline
        /// The file before on the left and after on the right, each line level with its
        /// counterpart.
        case sideBySide
    }

    enum Notice: Equatable, Sendable {
        case modeChange(String)
        case binary
        case tooLarge(lines: Int)
        case notRead(lines: Int)
        case reading
        case failed(summary: String)
        case noChanges(String)

        /// Left out changes the user can ask for.
        var offersToShow: Bool {
            switch self {
            case .tooLarge, .notRead, .failed: true
            default: false
            }
        }
    }

    enum Block: Equatable, Sendable {
        case header(file: Int)
        case notice(file: Int, Notice)
        /// Before and after, for an image.
        case images(file: Int)
        /// Above each hunk.
        case hunk(file: Int, hunk: Int)
        /// Indices into the hunk's lines. Inline, only `left` is set. Side by side, an unchanged
        /// line is on both sides, and a side is nil where the other has a line with no counterpart.
        case lines(file: Int, hunk: Int, left: Int?, right: Int?)

        var file: Int {
            switch self {
            case let .header(file), let .notice(file, _), let .images(file), let .hunk(file, _), let .lines(file, _, _, _): file
            }
        }
    }

    let style: Style
    /// Each file's own style, which is inline for an added or deleted file, whose other side would
    /// be empty.
    let fileStyles: [Style]
    let blocks: [Block]
    /// The index of each file's header in `blocks`.
    let fileStarts: [Int]

    init(files: [DiffFile], collapsed: Set<Int>, style: Style) {
        self.style = style
        fileStyles = files.map { Self.style(of: $0, in: style) }
        var blocks: [Block] = []
        var fileStarts: [Int] = []
        for (index, file) in files.enumerated() {
            fileStarts.append(blocks.count)
            blocks.append(.header(file: index))
            guard !collapsed.contains(index) else { continue }
            for notice in Self.notices(for: file) {
                blocks.append(.notice(file: index, notice))
            }
            if Self.showsImages(file) {
                blocks.append(.images(file: index))
            }
            for (hunkIndex, hunk) in file.patch.hunks.enumerated() {
                blocks.append(.hunk(file: index, hunk: hunkIndex))
                Self.appendLines(of: hunk, file: index, hunk: hunkIndex, style: fileStyles[index], to: &blocks)
            }
        }
        self.blocks = blocks
        self.fileStarts = fileStarts
    }

    /// The file a block belongs to.
    func file(at block: Int) -> Int? {
        blocks.indices.contains(block) ? blocks[block].file : nil
    }

    static func style(of file: DiffFile, in style: Style) -> Style {
        file.changed.change == .added || file.changed.change == .deleted ? .inline : style
    }

    /// The style a block is laid out in, which is its file's.
    func style(ofBlock block: Int) -> Style {
        fileStyles[blocks[block].file]
    }

    static func showsImages(_ file: DiffFile) -> Bool {
        file.changed.isImage && file.patch.isBinary && file.patch.content == .shown
    }

    static func notices(for file: DiffFile) -> [Notice] {
        var notices: [Notice] = []
        if let modeChange = file.changed.modeChange {
            notices.append(.modeChange(modeChange))
        }
        switch file.reading {
        case .reading:
            return notices + [.reading]
        case let .failed(summary):
            return notices + [.failed(summary: summary)]
        case .idle:
            break
        }
        let patch = file.patch
        switch patch.content {
        case .tooLarge:
            notices.append(.tooLarge(lines: patch.changedLines))
        case .notRead:
            notices.append(.notRead(lines: patch.changedLines))
        case .shown where patch.isBinary:
            if !showsImages(file) {
                notices.append(.binary)
            }
        case .shown where patch.hunks.isEmpty && notices.isEmpty:
            notices.append(.noChanges(noChangesReason(file.changed)))
        case .shown:
            break
        }
        return notices
    }

    private static func noChangesReason(_ file: ChangedFile) -> String {
        switch file.change {
        case .renamed: "Renamed without changes."
        case .copied: "Copied without changes."
        case .added, .deleted: "Empty file."
        default: "Only whitespace changed."
        }
    }

    private static func appendLines(of hunk: DiffHunk, file: Int, hunk hunkIndex: Int, style: Style, to blocks: inout [Block]) {
        guard style == .sideBySide else {
            for index in hunk.lines.indices {
                blocks.append(.lines(file: file, hunk: hunkIndex, left: index, right: nil))
            }
            return
        }
        var index = 0
        while index < hunk.lines.count {
            guard hunk.lines[index].kind != .context else {
                blocks.append(.lines(file: file, hunk: hunkIndex, left: index, right: index))
                index += 1
                continue
            }
            var removed: [Int] = []
            var added: [Int] = []
            while index < hunk.lines.count, hunk.lines[index].kind != .context {
                if hunk.lines[index].kind == .removed {
                    removed.append(index)
                } else {
                    added.append(index)
                }
                index += 1
            }
            for row in 0 ..< max(removed.count, added.count) {
                blocks.append(.lines(
                    file: file,
                    hunk: hunkIndex,
                    left: removed.indices.contains(row) ? removed[row] : nil,
                    right: added.indices.contains(row) ? added[row] : nil
                ))
            }
        }
    }
}
