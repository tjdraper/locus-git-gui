import Foundation
import Testing

struct PatchParserTests {
    private func parse(_ output: String, limits: PatchParser.Limits = .allFiles, pieceSize: Int? = nil) -> [FilePatch] {
        var parser = PatchParser(limits: limits)
        let data = Data(output.utf8)
        if let pieceSize {
            var start = 0
            while start < data.count {
                parser.consume(data[start ..< min(start + pieceSize, data.count)])
                start += pieceSize
            }
        } else {
            parser.consume(data)
        }
        return parser.finish()
    }

    @Test
    func eachFileHasItsHunksAndNumberedLines() {
        // Arrange
        let output = """
        diff --git a/a.txt b/a.txt
        index 1111111..2222222 100644
        --- a/a.txt
        +++ b/a.txt
        @@ -10,3 +10,3 @@ func main() {
         keep
        -old
        +new
         keep
        diff --git a/b.bin b/b.bin
        new file mode 100644
        index 0000000..3333333
        Binary files /dev/null and b/b.bin differ

        """

        // Act
        let files = parse(output)

        // Assert
        #expect(files.count == 2)
        #expect(files[0].fileLine == "diff --git a/a.txt b/a.txt")
        #expect(files[0].hunks.count == 1)
        #expect(files[0].hunks[0].section == "func main() {")
        #expect(files[0].hunks[0].lines.map(\.kind) == [.context, .removed, .added, .context])
        #expect(files[0].hunks[0].lines.map(\.text) == ["keep", "old", "new", "keep"])
        #expect(files[0].hunks[0].lines.map(\.oldNumber) == [10, 11, nil, 12])
        #expect(files[0].hunks[0].lines.map(\.newNumber) == [10, nil, 11, 12])
        #expect(files[0].added == 1)
        #expect(files[0].removed == 1)
        #expect(files[1].isBinary)
        #expect(files[1].hunks.isEmpty)
    }

    @Test
    func piecesSplitMidLineReadTheSame() {
        // Arrange
        let output = "diff --git a/a b/a\n@@ -1,2 +1,2 @@\n-first line\n+first LINE\n second line\n"

        // Act
        let whole = parse(output)
        let inPieces = parse(output, pieceSize: 3)

        // Assert
        #expect(whole == inPieces)
        #expect(whole[0].hunks[0].lines.count == 3)
    }

    @Test
    func aRemovedLineThatLooksLikeAHeaderIsKept() {
        // Arrange
        let output = "diff --git a/q.sql b/q.sql\n--- a/q.sql\n+++ b/q.sql\n@@ -1,2 +1 @@\n"
            + "--- a comment\n+++ counter\n \n\\ No newline at end of file\n"

        // Act
        let files = parse(output)

        // Assert
        #expect(files[0].hunks[0].lines.map(\.kind) == [.removed, .added, .context])
        #expect(files[0].hunks[0].lines.map(\.text) == ["-- a comment", "++ counter", ""])
        #expect(files[0].hunks[0].lines[2].hasNoNewlineAtEnd)
    }

    @Test
    func windowsLineEndingsAreLeftOffTheText() {
        // Arrange
        let output = "diff --git a/w.txt b/w.txt\n@@ -1 +1 @@\r\n-old\r\n+new\r\n"

        // Act
        let files = parse(output)

        // Assert
        #expect(files[0].hunks[0].lines.map(\.text) == ["old", "new"])
    }

    @Test
    func aFileWhoseTypeChangedIsOneFile() {
        // Arrange
        let output = "diff --git a/a b/a\ndeleted file mode 100644\n@@ -1 +0,0 @@\n-text\n"
            + "diff --git a/a b/a\nnew file mode 120000\n@@ -0,0 +1 @@\n+b.txt\n"

        // Act
        let files = parse(output)

        // Assert
        #expect(files.count == 1)
        #expect(files[0].hunks.count == 2)
    }

    @Test
    func aFilePastItsLimitIsCountedButNotKept() {
        // Arrange
        let limits = PatchParser.Limits(fileLines: 2, fileBytes: .max, totalLines: .max)
        let output = "diff --git a/big b/big\n@@ -0,0 +1,3 @@\n+1\n+2\n+3\ndiff --git a/small b/small\n@@ -1 +1 @@\n-a\n+b\n"

        // Act
        let files = parse(output, limits: limits)

        // Assert
        #expect(files[0].content == .tooLarge)
        #expect(files[0].hunks.isEmpty)
        #expect(files[0].added == 3)
        #expect(files[1].content == .shown)
        #expect(files[1].hunks[0].lines.count == 2)
    }

    @Test
    func anEnormousLineMakesItsFileTooLarge() {
        // Arrange
        let limits = PatchParser.Limits(fileLines: .max, fileBytes: 1000, totalLines: .max)
        let output = "diff --git a/min.js b/min.js\n@@ -0,0 +1 @@\n+" + String(repeating: "x", count: 5000) + "\n"

        // Act
        let files = parse(output, limits: limits)

        // Assert
        #expect(files[0].content == .tooLarge)
        #expect(files[0].changedLines == 1)
    }

    @Test
    func filesAfterTheTotalLimitAreNotRead() {
        // Arrange
        let limits = PatchParser.Limits(fileLines: .max, fileBytes: .max, totalLines: 2)
        let output = "diff --git a/a b/a\n@@ -1 +1 @@\n-a\n+b\ndiff --git a/c b/c\n@@ -1 +1 @@\n-c\n+d\n"

        // Act
        let files = parse(output, limits: limits)

        // Assert
        #expect(files[0].content == .shown)
        #expect(files[1].content == .notRead)
        #expect(files[1].changedLines == 2)
    }

    @Test
    func noOutputIsNoFiles() {
        // Act
        let files = parse("")

        // Assert
        #expect(files.isEmpty)
    }
}
