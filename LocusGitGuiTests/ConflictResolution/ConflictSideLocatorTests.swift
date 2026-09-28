import Foundation
import Testing

struct ConflictSideLocatorTests {
    @Test
    func eachSideIsFoundInItsFile() {
        // Arrange
        let result = "a\n<<<<<<< HEAD\nb\n=======\nB\n>>>>>>> x\nc\nd\n<<<<<<< HEAD\ne\nf\n=======\nE\n>>>>>>> x\n"
        let ours = "a\nb\nc\nd\ne\nf\n"
        let theirs = "a\nB\nc\nd\nE\n"
        let markers = ConflictMarkers(parsing: result)

        // Act
        let inOurs = ConflictSideLocator(file: ours).locate(.ours, of: markers, in: result)
        let inTheirs = ConflictSideLocator(file: theirs).locate(.theirs, of: markers, in: result)

        // Assert
        #expect(inOurs == [1 ..< 2, 4 ..< 6])
        #expect(inTheirs == [1 ..< 2, 4 ..< 5])
    }

    @Test
    func aRepeatedSideIsFoundAfterTheOneBefore() {
        // Arrange
        let result = "<<<<<<< HEAD\n}\n=======\n>>>>>>> x\nmiddle\n<<<<<<< HEAD\n}\n=======\n>>>>>>> x\n"
        let ours = "}\nmiddle\n}\n"
        let markers = ConflictMarkers(parsing: result)

        // Act
        let located = ConflictSideLocator(file: ours).locate(.ours, of: markers, in: result)

        // Assert
        #expect(located == [0 ..< 1, 2 ..< 3])
    }

    @Test
    func aSideWithNoLinesSitsAfterTheLinesBeforeIt() {
        // Arrange
        let result = "a\nb\n<<<<<<< HEAD\nours\n=======\n>>>>>>> x\nc\n"
        let theirs = "a\nb\nc\n"
        let markers = ConflictMarkers(parsing: result)

        // Act
        let located = ConflictSideLocator(file: theirs).locate(.theirs, of: markers, in: result)

        // Assert
        #expect(located == [2 ..< 2])
    }

    @Test
    func theAncestorIsOnlyFoundWhenGitWroteIt() {
        // Arrange
        let result = "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n"
        let markers = ConflictMarkers(parsing: result)

        // Act
        let located = ConflictSideLocator(file: "c\n").locate(.base, of: markers, in: result)

        // Assert
        #expect(located == [nil])
    }

    @Test
    func windowsLineEndingsMatchUnixOnes() {
        // Arrange
        let result = "<<<<<<< HEAD\r\nb\r\n=======\r\nB\r\n>>>>>>> x\r\n"
        let markers = ConflictMarkers(parsing: result)

        // Act
        let located = ConflictSideLocator(file: "a\nb\n").locate(.ours, of: markers, in: result)

        // Assert
        #expect(located == [1 ..< 2])
    }

    @Test
    func linesBecomeCharacters() {
        // Arrange
        let locator = ConflictSideLocator(file: "ab\nc\nd")

        // Assert
        #expect(locator.characters(of: 1 ..< 2) == NSRange(location: 3, length: 2))
        #expect(locator.characters(of: 2 ..< 3) == NSRange(location: 5, length: 1))
        #expect(locator.characters(of: 3 ..< 3) == NSRange(location: 6, length: 0))
    }

    @Test
    func lineStartsEndWithTheTextsEnd() {
        // Assert
        #expect(ConflictSideLocator.lineStarts(of: "ab\nc\n") == [0, 3, 5])
        #expect(ConflictSideLocator.lineStarts(of: "ab\nc") == [0, 3, 4])
        #expect(ConflictSideLocator.lineStarts(of: "é\n👋\n") == [0, 2, 5])
        #expect(ConflictSideLocator.lineStarts(of: "") == [0])
    }
}
