import Foundation
import Testing

struct ChangedWordsTests {
    private func marked(_ text: String, _ ranges: [Range<Int>]) -> [String] {
        let units = Array(text.utf16)
        return ranges.map { String(utf16CodeUnits: Array(units[$0]), count: $0.count) }
    }

    @Test
    func marksTheWordsThatChanged() throws {
        // Arrange
        let old = "let count = items.count + 1"
        let new = "let total = items.count + 2"

        // Act
        let ranges = try #require(ChangedWords.compare(old, new))

        // Assert
        #expect(marked(old, ranges.old) == ["count", "1"])
        #expect(marked(new, ranges.new) == ["total", "2"])
    }

    @Test
    func changedWordsWithOnlySpacesBetweenAreOneMark() throws {
        // Arrange
        let old = "The quick brown fox jumps"
        let new = "The slow red fox jumps"

        // Act
        let ranges = try #require(ChangedWords.compare(old, new))

        // Assert
        #expect(marked(new, ranges.new) == ["slow red"])
    }

    @Test
    func anAddedWordOnlyMarksTheNewLine() throws {
        // Arrange
        let old = "View > Show Git Log): every command"
        let new = "View > Show Git Log, which slice 7 turns into View > Show Activity): every command"

        // Act
        let ranges = try #require(ChangedWords.compare(old, new))

        // Assert
        #expect(ranges.old.isEmpty)
        #expect(marked(new, ranges.new) == [", which slice 7 turns into View > Show Activity"])
    }

    @Test
    func linesWithLittleInCommonAreNotMarked() {
        // Act
        let ranges = ChangedWords.compare("import Foundation", "return value * 2")

        // Assert
        #expect(ranges == nil)
    }

    @Test
    func identicalLinesAreNotMarked() {
        // Act
        let ranges = ChangedWords.compare("same", "same")

        // Assert
        #expect(ranges == nil)
    }

    @Test
    func rangesCountUTF16() throws {
        // Arrange
        let old = "café 😀 old"
        let new = "café 😀 new"

        // Act
        let ranges = try #require(ChangedWords.compare(old, new))

        // Assert
        #expect(ranges.new == [8 ..< 11])
    }
}
