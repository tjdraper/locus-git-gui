import Foundation
import Testing

struct FuzzyMatcherTests {
    @Test
    func matchesLettersInOrderAnywhereInTheName() {
        // Arrange
        let matcher = FuzzyMatcher(name: "Safari")

        // Act
        let inOrder = score("sfr", in: matcher)
        let outOfOrder = score("rfs", in: matcher)

        // Assert
        #expect(inOrder != nil)
        #expect(outOfOrder == nil)
    }

    @Test
    func matchesTheStartsOfWords() {
        // Arrange
        let matcher = FuzzyMatcher(name: "Visual Studio Code")

        // Act
        let result = score("vsc", in: matcher)

        // Assert
        #expect(result != nil)
    }

    @Test
    func ranksWordStartsAboveLettersInsideWords() throws {
        // Arrange
        let wordStarts = FuzzyMatcher(name: "Visual Studio Code")
        let insideWords = FuzzyMatcher(name: "Movies Scene")

        // Act
        let wordStartScore = score("vsc", in: wordStarts)
        let insideScore = score("vsc", in: insideWords)

        // Assert
        #expect(try #require(wordStartScore) > #require(insideScore))
    }

    @Test
    func ranksAPrefixAboveScatteredLetters() throws {
        // Arrange
        let prefix = FuzzyMatcher(name: "Safari")
        let scattered = FuzzyMatcher(name: "Screen Sharing Assistant Framework")

        // Act
        let prefixScore = score("saf", in: prefix)
        let scatteredScore = score("saf", in: scattered)

        // Assert
        #expect(try #require(prefixScore) > #require(scatteredScore))
    }

    @Test
    func treatsCamelCaseHumpsAsWordStarts() throws {
        // Arrange
        let camelCase = FuzzyMatcher(name: "TextEdit")
        let plain = FuzzyMatcher(name: "Textedit")

        // Act
        let camelScore = score("tee", in: camelCase)
        let plainScore = score("tee", in: plain)

        // Assert
        #expect(try #require(camelScore) > #require(plainScore))
    }

    @Test
    func ignoresCaseAccentsAndSpaces() {
        // Arrange
        let matcher = FuzzyMatcher(name: "Éclair Notes")

        // Act
        let result = score("ECL no", in: matcher)

        // Assert
        #expect(result != nil)
    }

    private func score(_ query: String, in matcher: FuzzyMatcher) -> Int? {
        matcher.score(Array(FuzzyMatcher.fold(query)))
    }
}
