import Foundation
import Testing

struct LineWrapTests {
    private func lines(_ text: String, columns: Int) -> [String] {
        let units = Array(text.utf16)
        return LineWrap.wrap(units, columns: columns).ranges(length: units.count).map {
            String(utf16CodeUnits: Array(units[$0]), count: $0.count)
        }
    }

    @Test
    func aLineThatFitsIsOneLine() {
        // Act
        let wrapped = lines("short", columns: 10)

        // Assert
        #expect(wrapped == ["short"])
    }

    @Test
    func breaksAfterASpace() {
        // Act
        let wrapped = lines("one two three four", columns: 9)

        // Assert
        #expect(wrapped == ["one two ", "three ", "four"])
    }

    @Test
    func aWordWiderThanTheLineBreaksWithinIt() {
        // Act
        let wrapped = lines("abcdefghij", columns: 4)

        // Assert
        #expect(wrapped == ["abcd", "ef", "gh", "ij"])
    }

    @Test
    func continuationLinesStartAfterTheirMarker() {
        // Act
        let result = LineWrap.wrap(Array("one two three".utf16), columns: 8)

        // Assert
        #expect(result.textColumn(ofLine: 0) == 0)
        #expect(result.textColumn(ofLine: 1) == LineWrap.markerColumns)
    }

    @Test
    func continuationLinesKeepTheIndentation() {
        // Act
        let result = LineWrap.wrap(Array("    one two three".utf16), columns: 12)

        // Assert
        #expect(result.indent == 4)
        #expect(lines("    one two three", columns: 12) == ["    one two ", "three"])
    }

    @Test
    func indentationPastHalfTheLineIsDropped() {
        // Act
        let result = LineWrap.wrap(Array("        word word".utf16), columns: 12)

        // Assert
        #expect(result.indent == 0)
    }

    @Test
    func tabsReachTheNextStop() {
        // Act
        let width = LineWrap.width(of: "\tab\tc".utf16)

        // Assert
        #expect(width == 9)
    }

    @Test
    func wideCharactersTakeTwoColumns() {
        // Act
        let width = LineWrap.width(of: "日本😀".utf16)

        // Assert
        #expect(width == 6)
    }

    @Test
    func anEmojiIsNeverSplit() {
        // Act
        let wrapped = lines("abc😀d", columns: 4)

        // Assert
        #expect(wrapped == ["abc", "😀", "d"])
    }

    @Test
    func anEnormousLineBreaksEverySoManyCharacters() {
        // Arrange
        let units = Array(String(repeating: "word ", count: LineWrap.longLine).utf16)

        // Act
        let result = LineWrap.wrap(units, columns: 100)

        // Assert
        #expect(result.breaks.prefix(3) == [100, 198, 296])
        #expect(result.count == LineWrap.longLineCount(length: units.count, columns: 100))
    }
}
