import Foundation
import Testing

struct DiffSelectionTests {
    private let files: [DiffFile] = {
        var parser = PatchParser(limits: .allFiles)
        parser.consume(Data("diff --git a/a.txt b/a.txt\n@@ -1,4 +1,4 @@\n keep\n-one\n-two\n+ONE\n keep\n".utf8))
        return [DiffFile(changed: ChangedFile(change: .modified, path: "a.txt", originalPath: nil), patch: parser.finish()[0])]
    }()

    private func selection(from start: (Int, Int), to end: (Int, Int), side: Int = 0) -> DiffSelection {
        DiffSelection(
            side: side,
            anchor: DiffSelection.Point(block: start.0, offset: start.1),
            head: DiffSelection.Point(block: end.0, offset: end.1)
        )
    }

    @Test
    func sideBySideASelectionTakesBothSidesOfEachRow() {
        // Arrange
        let document = DiffDocument(files: files, collapsed: [], style: .sideBySide)
        // The row pairing the removed "one" with the added "ONE".
        let row = 3

        // Act
        let lines = selection(from: (row, 0), to: (row, 2)).lines(inFile: 0, hunk: 0, document: document)

        // Assert
        #expect(lines == [1, 3])
    }

    @Test
    func aRowTheSelectionOnlyReachesTheStartOfIsLeftOut() {
        // Arrange
        let document = DiffDocument(files: files, collapsed: [], style: .inline)

        // Act
        let lines = selection(from: (3, 1), to: (5, 0)).lines(inFile: 0, hunk: 0, document: document)

        // Assert
        #expect(lines == [1, 2])
    }

    @Test
    func anEmptySelectionHasNoLines() {
        // Arrange
        let document = DiffDocument(files: files, collapsed: [], style: .inline)

        // Act
        let lines = selection(from: (3, 1), to: (3, 1)).lines(inFile: 0, hunk: 0, document: document)

        // Assert
        #expect(lines.isEmpty)
    }

    private let metrics = DiffLayout.Metrics(advance: 7, lineHeight: 16)

    private func file(_ path: String, group: Int? = nil) -> DiffFile {
        DiffFile(changed: ChangedFile(change: .modified, path: path, originalPath: nil), patch: files[0].patch, group: group)
    }

    @Test
    func theMarkPassesToTheNextFileWhenItsFileGoes() {
        // Arrange
        let before = [file("a", group: 2), file("b", group: 2), file("c", group: 2)]
        let after = [file("b", group: 1), file("a", group: 2), file("c", group: 2)]

        // Act
        let marked = DiffCommandTarget.markedFile(before[1].id, from: before, in: after)

        // Assert
        #expect(marked == after[2].id)
    }

    @Test
    func theMarkPassesBackWhenTheLastFileGoes() {
        // Arrange
        let before = [file("a"), file("b")]

        // Act
        let marked = DiffCommandTarget.markedFile(before[1].id, from: before, in: [file("a")])

        // Assert
        #expect(marked == before[0].id)
    }

    private func layout(of document: DiffDocument) -> DiffLayout {
        DiffLayout(document: document, files: files, metrics: DiffLayout.Metrics(advance: 7, lineHeight: 16), width: 800, numberColumns: 3)
    }

    @Test
    func theCurrentHunkIsTheOneWithTheSelection() {
        // Arrange
        let document = DiffDocument(files: files, collapsed: [], style: .inline)
        let layout = layout(of: document)
        let target = DiffCommandTarget(
            document: document,
            layout: layout,
            selection: selection(from: (4, 0), to: (4, 1)),
            visibleTop: 0,
            visibleBottom: layout.height
        )

        // Act
        let hunk = target.hunk

        // Assert
        #expect(hunk == DiffCommandTarget.Hunk(file: 0, hunk: 0))
    }

    @Test
    func theMarkedFileIsCurrentWhileItsInView() {
        // Arrange
        let two = files + [file("b.txt")]
        let document = DiffDocument(files: two, collapsed: [], style: .inline)
        let layout = DiffLayout(document: document, files: two, metrics: metrics, width: 800, numberColumns: 3)
        let inView = DiffCommandTarget(
            document: document, layout: layout, selection: nil, visibleTop: 32, visibleBottom: layout.height, markedFile: 1
        )
        let outOfView = DiffCommandTarget(
            document: document, layout: layout, selection: nil, visibleTop: 32, visibleBottom: 40, markedFile: 1
        )

        // Act
        let marked = inView.file
        let top = outOfView.file

        // Assert
        #expect(marked == 1)
        #expect(top == 0)
    }

    @Test
    func withoutASelectionTheCurrentHunkIsTheFirstInView() {
        // Arrange
        let document = DiffDocument(files: files, collapsed: [], style: .inline)
        let layout = layout(of: document)
        let target = DiffCommandTarget(document: document, layout: layout, selection: nil, visibleTop: 0, visibleBottom: layout.height)

        // Act
        let hunk = target.hunk

        // Assert
        #expect(hunk == DiffCommandTarget.Hunk(file: 0, hunk: 0))
    }
}
