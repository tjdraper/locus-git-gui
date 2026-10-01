import Foundation
import Testing

struct DiffInsertTests {
    /// One hunk: line 1 unchanged, line 2 replaced, line 3 added.
    private func file() -> DiffFile {
        var hunk = DiffHunk(oldStart: 1, newStart: 1, section: "")
        hunk.lines = [
            DiffLine(kind: .context, text: "one", oldNumber: 1, newNumber: 1),
            DiffLine(kind: .removed, text: "two", oldNumber: 2, newNumber: nil),
            DiffLine(kind: .added, text: "2", oldNumber: nil, newNumber: 2),
            DiffLine(kind: .added, text: "three", oldNumber: nil, newNumber: 3),
        ]
        var patch = FilePatch(fileLine: "diff --git a/a b/a")
        patch.hunks = [hunk]
        return DiffFile(changed: ChangedFile(change: .modified, path: "a", originalPath: nil), patch: patch)
    }

    private func id() -> DiffFile.Identity {
        DiffFile.Identity(group: nil, path: "a")
    }

    @Test
    func anInsertGoesBelowItsLineOnItsSide() {
        // Arrange
        let inserts = [
            DiffInsert(id: "old", file: id(), place: .line(.old, 2)),
            DiffInsert(id: "new", file: id(), place: .line(.new, 2)),
            DiffInsert(id: "top", file: id(), place: .top),
        ]

        // Act
        let document = DiffDocument(files: [file()], collapsed: [], style: .inline, inserts: inserts)

        // Assert
        #expect(document.blocks == [
            .header(file: 0),
            .insert(file: 0, id: "top"),
            .hunk(file: 0, hunk: 0),
            .lines(file: 0, hunk: 0, left: 0, right: nil),
            .lines(file: 0, hunk: 0, left: 1, right: nil),
            .insert(file: 0, id: "old"),
            .lines(file: 0, hunk: 0, left: 2, right: nil),
            .insert(file: 0, id: "new"),
            .lines(file: 0, hunk: 0, left: 3, right: nil),
        ])
    }

    @Test
    func aLineTheDiffDoesntShowPutsTheInsertBelowTheNearestBefore() {
        // Arrange
        let inserts = [DiffInsert(id: "far", file: id(), place: .line(.new, 40))]

        // Act
        let document = DiffDocument(files: [file()], collapsed: [], style: .sideBySide, inserts: inserts)

        // Assert
        #expect(document.blocks.last == .insert(file: 0, id: "far"))
    }

    @Test
    func anInsertTakesTheHeightItsGiven() {
        // Arrange
        let inserts = [DiffInsert(id: "top", file: id(), place: .top)]
        let document = DiffDocument(files: [file()], collapsed: [], style: .inline, inserts: inserts)
        let metrics = DiffLayout.Metrics(advance: 7, lineHeight: 16)

        // Act
        let layout = DiffLayout(
            document: document,
            files: [file()],
            metrics: metrics,
            width: 800,
            numberColumns: 3,
            insertHeights: ["top": 90]
        )

        // Assert
        #expect(layout.frame(of: 1).maxY - layout.frame(of: 1).minY == 90)
    }

    @Test
    func aSelectionAcrossRemovedAndAddedLinesIsOnTheNewSide() {
        // Arrange
        let document = DiffDocument(files: [file()], collapsed: [], style: .inline)

        // Act
        let target = DiffLineTarget(blocks: 3 ... 5, side: 0, document: document, files: [file()])

        // Assert
        #expect(target == DiffLineTarget(file: id(), side: .new, lines: 2 ... 3, text: ["2", "three"]))
    }

    @Test
    func aRemovedLineAloneIsOnTheOldSide() {
        // Arrange
        let document = DiffDocument(files: [file()], collapsed: [], style: .inline)

        // Act
        let target = DiffLineTarget(blocks: 3 ... 3, side: 0, document: document, files: [file()])

        // Assert
        #expect(target == DiffLineTarget(file: id(), side: .old, lines: 2 ... 2, text: ["two"]))
    }
}
