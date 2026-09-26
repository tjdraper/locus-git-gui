import Foundation
import Testing

struct DiffDocumentTests {
    private func file(_ patch: String, change: ChangedFile.Change = .modified, path: String = "a.txt") -> DiffFile {
        var parser = PatchParser(limits: .allFiles)
        parser.consume(Data(patch.utf8))
        return DiffFile(
            changed: ChangedFile(change: change, path: path, originalPath: nil, oldMode: "100644", newMode: "100644"),
            patch: parser.finish().first ?? FilePatch()
        )
    }

    private let edit = "diff --git a/a.txt b/a.txt\n@@ -1,4 +1,4 @@\n keep\n-one\n-two\n+ONE\n keep\n"

    @Test
    func inlineHasARowForEveryLine() {
        // Act
        let document = DiffDocument(files: [file(edit)], collapsed: [], style: .inline)

        // Assert
        #expect(document.blocks == [
            .header(file: 0),
            .hunk(file: 0, hunk: 0),
            .lines(file: 0, hunk: 0, left: 0, right: nil),
            .lines(file: 0, hunk: 0, left: 1, right: nil),
            .lines(file: 0, hunk: 0, left: 2, right: nil),
            .lines(file: 0, hunk: 0, left: 3, right: nil),
            .lines(file: 0, hunk: 0, left: 4, right: nil),
        ])
    }

    @Test
    func sideBySidePairsRemovedLinesWithTheAddedLinesAfterThem() {
        // Act
        let document = DiffDocument(files: [file(edit)], collapsed: [], style: .sideBySide)

        // Assert
        #expect(document.blocks.dropFirst(2) == [
            .lines(file: 0, hunk: 0, left: 0, right: 0),
            .lines(file: 0, hunk: 0, left: 1, right: 3),
            .lines(file: 0, hunk: 0, left: 2, right: nil),
            .lines(file: 0, hunk: 0, left: 4, right: 4),
        ])
    }

    @Test
    func aCollapsedFileIsOnlyItsHeader() {
        // Act
        let document = DiffDocument(files: [file(edit), file(edit)], collapsed: [0], style: .inline)

        // Assert
        #expect(document.blocks.prefix(2) == [.header(file: 0), .header(file: 1)])
        #expect(document.fileStarts == [0, 1])
    }

    @Test
    func pairedLinesHaveTheirChangedWordsMarked() {
        // Arrange
        let changed = file("diff --git a/a b/a\n@@ -1 +1 @@\n-let count = 1\n+let count = 2\n")

        // Assert
        #expect(changed.patch.hunks[0].lines[0].changedWords == [12 ..< 13])
        #expect(changed.patch.hunks[0].lines[1].changedWords == [12 ..< 13])
    }

    @Test
    func aRenameWithoutChangesSaysSo() {
        // Arrange
        let renamed = file("diff --git a/a b/b\nsimilarity index 100%\nrename from a\nrename to b\n", change: .renamed)

        // Act
        let document = DiffDocument(files: [renamed], collapsed: [], style: .inline)

        // Assert
        #expect(document.blocks == [.header(file: 0), .notice(file: 0, .noChanges("Renamed without changes."))])
    }

    @Test
    func aBinaryImageShowsItsImagesAndOtherBinariesSaySo() {
        // Arrange
        let binary = "diff --git a/x b/x\nBinary files a/x and b/x differ\n"

        // Act
        let document = DiffDocument(
            files: [file(binary, path: "icon.png"), file(binary, path: "data.bin")],
            collapsed: [],
            style: .inline
        )

        // Assert
        #expect(document.blocks == [.header(file: 0), .images(file: 0), .header(file: 1), .notice(file: 1, .binary)])
    }

    @Test
    func leftOutChangesOfferToBeShown() {
        // Arrange
        var large = file(edit)
        large.patch.content = .tooLarge
        large.patch.hunks = []

        // Act
        let document = DiffDocument(files: [large], collapsed: [], style: .inline)

        // Assert
        #expect(document.blocks == [.header(file: 0), .notice(file: 0, .tooLarge(lines: 3))])
    }

    @Test
    func anAddedFileIsInlineInASideBySideDiff() {
        // Arrange
        let added = file("diff --git a/n b/n\n@@ -0,0 +1,2 @@\n+one\n+two\n", change: .added, path: "n")

        // Act
        let document = DiffDocument(files: [file(edit), added], collapsed: [], style: .sideBySide)

        // Assert
        #expect(document.fileStyles == [.sideBySide, .inline])
        #expect(document.blocks.suffix(2) == [
            .lines(file: 1, hunk: 0, left: 0, right: nil),
            .lines(file: 1, hunk: 0, left: 1, right: nil),
        ])
    }
}
