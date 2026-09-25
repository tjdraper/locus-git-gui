import Foundation
import Testing

struct SidebarTypeSelectTests {
    private let names = ["develop", "feature/login", "feature/signup", "main", "Émile"]
    private let start = Date(timeIntervalSince1970: 0)

    @Test
    func typingSelectsTheFirstNameThatStartsWithIt() {
        // Arrange
        var typeSelect = SidebarTypeSelect()

        // Act
        let index = typeSelect.select(typing: "m", at: start, in: names, selected: nil)

        // Assert
        #expect(index == 3)
    }

    @Test
    func keysTypedQuicklyAddToOneSearch() {
        // Arrange
        var typeSelect = SidebarTypeSelect()
        let first = typeSelect.select(typing: "f", at: start, in: names, selected: nil)

        // Act
        let index = typeSelect.select(typing: "eature/s", at: start + 0.3, in: names, selected: first)

        // Assert
        #expect(first == 1)
        #expect(index == 2)
        #expect(typeSelect.search == "feature/s")
    }

    @Test
    func aLongerSearchKeepsTheSelectedRowWhileItStillMatches() {
        // Arrange
        var typeSelect = SidebarTypeSelect()
        let first = typeSelect.select(typing: "f", at: start, in: names, selected: nil)

        // Act
        let index = typeSelect.select(typing: "e", at: start + 0.3, in: names, selected: first)

        // Assert
        #expect(index == 1)
    }

    @Test
    func typingTheSameLetterAfterAPauseMovesToTheNextMatch() {
        // Arrange
        var typeSelect = SidebarTypeSelect()
        let first = typeSelect.select(typing: "f", at: start, in: names, selected: nil)

        // Act
        let index = typeSelect.select(typing: "f", at: start + SidebarTypeSelect.pause + 0.1, in: names, selected: first)

        // Assert
        #expect(index == 2)
        #expect(typeSelect.search == "f")
    }

    @Test
    func theSearchWrapsAroundToTheTop() {
        // Arrange
        var typeSelect = SidebarTypeSelect()

        // Act
        let index = typeSelect.select(typing: "d", at: start, in: names, selected: 3)

        // Assert
        #expect(index == 0)
    }

    @Test
    func caseAndAccentsDontMatter() {
        // Arrange
        var typeSelect = SidebarTypeSelect()

        // Act
        let main = typeSelect.select(typing: "MAIN", at: start, in: names, selected: nil)
        let emile = typeSelect.select(typing: "emi", at: start + 5, in: names, selected: nil)

        // Assert
        #expect(main == 3)
        #expect(emile == 4)
    }

    @Test
    func noMatchSelectsNothing() {
        // Arrange
        var typeSelect = SidebarTypeSelect()

        // Act
        let index = typeSelect.select(typing: "x", at: start, in: names, selected: 1)

        // Assert
        #expect(index == nil)
    }
}
