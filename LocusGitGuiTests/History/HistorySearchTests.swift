import Testing

struct HistorySearchTests {
    @Test
    func blankTextIsNoSearch() {
        // Act
        let search = HistorySearch(text: "  ", field: .message)

        // Assert
        #expect(search == nil)
    }

    @Test
    func surroundingSpacesAreIgnored() {
        // Act
        let search = HistorySearch(text: " fix ", field: .author)

        // Assert
        #expect(search?.text == "fix")
    }

    @Test
    func somethingThatCouldBeAHashIsAlsoLookedUpAsOne() {
        // Act
        let hash = HistorySearch(text: "1a2B3c", field: .message)
        let tooShort = HistorySearch(text: "1a2", field: .message)
        let word = HistorySearch(text: "fix", field: .message)
        let author = HistorySearch(text: "cafe", field: .author)

        // Assert
        #expect(hash?.hashCandidate == "1a2B3c")
        #expect(tooShort?.hashCandidate == nil)
        #expect(word?.hashCandidate == nil)
        #expect(author?.hashCandidate == nil)
    }
}
