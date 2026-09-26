import Foundation
import Testing

struct CommitPatchTests {
    @Test
    func eachFileHasItsOwnSectionWithoutGitsRepeatedHeaders() {
        // Arrange
        let output = """
        diff --git a/a.txt b/a.txt
        index 1111111..2222222 100644
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -old
        +new
        diff --git a/b.bin b/b.bin
        new file mode 100644
        index 0000000..3333333
        Binary files /dev/null and b/b.bin differ

        """

        // Act
        let patch = CommitPatch(parsing: Data(output.utf8))

        // Assert
        #expect(patch.files == [
            [
                .init(kind: .hunkHeader, text: "@@ -1 +1 @@"),
                .init(kind: .removed, text: "-old"),
                .init(kind: .added, text: "+new"),
            ],
            [
                .init(kind: .fileInfo, text: "new file mode 100644"),
                .init(kind: .fileInfo, text: "Binary files /dev/null and b/b.bin differ"),
            ],
        ])
        #expect(!patch.isShortened)
    }

    @Test
    func aRemovedLineThatLooksLikeAHeaderIsKept() {
        // Arrange
        let output = "diff --git a/q.sql b/q.sql\n--- a/q.sql\n+++ b/q.sql\n@@ -1,2 +1 @@\n"
            + "--- a comment\n+++ counter\n \n\\ No newline at end of file\n"

        // Act
        let patch = CommitPatch(parsing: Data(output.utf8))

        // Assert
        #expect(patch.files.first?.map(\.kind) == [.hunkHeader, .removed, .added, .context, .note])
    }

    @Test
    func windowsLineEndingsAreSplitIntoLines() {
        // Arrange
        let output = "diff --git a/w.txt b/w.txt\n@@ -1 +1 @@\r\n-old\r\n+new\r\n"

        // Act
        let patch = CommitPatch(parsing: Data(output.utf8))

        // Assert
        #expect(patch.files.first?.map(\.text) == ["@@ -1 +1 @@", "-old", "+new"])
    }

    @Test
    func noChangesIsNoFiles() {
        // Act
        let patch = CommitPatch(parsing: Data())

        // Assert
        #expect(patch.files.isEmpty)
    }

    @Test
    func anEnormousPatchIsCutAtALineBoundary() {
        // Arrange
        let line = "+" + String(repeating: "x", count: 99) + "\n"
        let output = "diff --git a/big b/big\n@@ -0,0 +1 @@\n" + String(repeating: line, count: CommitPatch.displayLimit / 100 + 10)

        // Act
        let patch = CommitPatch(parsing: Data(output.utf8))

        // Assert
        #expect(patch.isShortened)
        #expect(patch.files.first?.dropFirst().allSatisfy { $0.text == String(line.dropLast()) } == true)
    }
}
