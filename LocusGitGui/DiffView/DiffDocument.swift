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
        /// Above the first file of each group in a grouped diff, such as the working area's staged
        /// changes. It belongs to that file.
        case group(file: Int)
        /// Space above a file's header, which sets it apart from the file before when that one is
        /// expanded. It belongs to the file below it.
        case gap(file: Int)
        case header(file: Int)
        case notice(file: Int, Notice)
        /// Before and after, for an image.
        case images(file: Int)
        /// Above each hunk.
        case hunk(file: Int, hunk: Int)
        /// Indices into the hunk's lines. Inline, only `left` is set. Side by side, an unchanged
        /// line is on both sides, and a side is nil where the other has a line with no counterpart.
        case lines(file: Int, hunk: Int, left: Int?, right: Int?)
        /// Room for something whoever shows the diff puts into it, by the insert's id.
        case insert(file: Int, id: String)

        var file: Int {
            switch self {
            case let .group(file), let .gap(file), let .header(file), let .notice(file, _), let .images(file),
                 let .hunk(file, _), let .lines(file, _, _, _), let .insert(file, _): file
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
    /// The index of the block after each file's last one, which is the group heading or the space
    /// above the next file.
    let fileEnds: [Int]
    /// The index of the heading of each file's group, or nil when the diff doesn't head groups.
    let fileGroupHeadings: [Int?]
    /// For each group heading's index, the index of the block after the group's last.
    let groupEnds: [Int: Int]

    /// `headsGroups` is false for a diff that doesn't show its files' groups, such as a file window
    /// showing one of the working area's files.
    init(files: [DiffFile], collapsed: Set<Int>, style: Style, headsGroups: Bool = true, inserts: [DiffInsert] = []) {
        self.style = style
        fileStyles = files.map { Self.style(of: $0, in: style) }
        var blocks: [Block] = []
        var fileStarts: [Int] = []
        var fileEnds: [Int] = []
        for (index, file) in files.enumerated() {
            if index > 0 {
                fileEnds.append(blocks.count)
            }
            if headsGroups, file.group != nil, index == 0 || files[index - 1].group != file.group {
                blocks.append(.group(file: index))
            } else if index > 0, !collapsed.contains(index - 1) {
                blocks.append(.gap(file: index))
            }
            fileStarts.append(blocks.count)
            blocks.append(.header(file: index))
            guard !collapsed.contains(index) else { continue }
            for notice in Self.notices(for: file) {
                blocks.append(.notice(file: index, notice))
            }
            if Self.showsImages(file) {
                blocks.append(.images(file: index))
            }
            var rows: [Block] = []
            for (hunkIndex, hunk) in file.patch.hunks.enumerated() {
                rows.append(.hunk(file: index, hunk: hunkIndex))
                Self.appendLines(of: hunk, file: index, hunk: hunkIndex, style: fileStyles[index], to: &rows)
            }
            let fileInserts = inserts.filter { $0.file == file.id }
            blocks += fileInserts.isEmpty ? rows : Self.placing(fileInserts, in: rows, of: file, at: index)
        }
        if !files.isEmpty {
            fileEnds.append(blocks.count)
        }
        self.blocks = blocks
        self.fileStarts = fileStarts
        self.fileEnds = fileEnds
        (fileGroupHeadings, groupEnds) = Self.groups(of: files, blocks: blocks, fileStarts: fileStarts)
    }

    private static func groups(of files: [DiffFile], blocks: [Block], fileStarts: [Int]) -> (headings: [Int?], ends: [Int: Int]) {
        var headings: [Int?] = []
        var ends: [Int: Int] = [:]
        var heading: Int?
        for (index, start) in fileStarts.enumerated() {
            if start > 0, case .group = blocks[start - 1] {
                if let heading {
                    ends[heading] = start - 1
                }
                heading = start - 1
            }
            headings.append(files[index].group == nil ? nil : heading)
        }
        if let heading {
            ends[heading] = blocks.count
        }
        return (headings, ends)
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
        case .unmerged: "This file has conflicts to resolve."
        default: "Only whitespace changed."
        }
    }

    /// Each insert below the last row whose line on its side is at or before the insert's line,
    /// and those at the top, or before every such row, above the first hunk.
    private static func placing(_ inserts: [DiffInsert], in rows: [Block], of file: DiffFile, at fileIndex: Int) -> [Block] {
        var below: [Int: [Block]] = [:]
        var top: [Block] = []
        for insert in inserts {
            let block = Block.insert(file: fileIndex, id: insert.id)
            guard case let .line(side, number) = insert.place else {
                top.append(block)
                continue
            }
            let row = rows.indices.last { index in
                lineNumber(of: rows[index], side: side, in: file).map { $0 <= number } ?? false
            }
            if let row {
                below[row, default: []].append(block)
            } else {
                top.append(block)
            }
        }
        var placed = top
        for (index, row) in rows.enumerated() {
            placed.append(row)
            placed += below[index] ?? []
        }
        return placed
    }

    /// The line a row shows on a side, counted from 1, whatever the row's style.
    private static func lineNumber(of block: Block, side: DiffInsert.Side, in file: DiffFile) -> Int? {
        guard case let .lines(_, hunk, left, right) = block else { return nil }
        let lines = file.patch.hunks[hunk].lines
        let shown = [left, right].compactMap(\.self).map { lines[$0] }
        return shown.lazy.compactMap { side == .old ? $0.oldNumber : $0.newNumber }.first
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
