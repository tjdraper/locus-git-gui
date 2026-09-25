import Foundation
import Testing

struct GitChoiceTests {
    private let suiteName = "GitChoiceTests-\(UUID().uuidString)"

    private func makeChoice() throws -> GitChoice {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return GitChoice(defaults: defaults)
    }

    @Test
    func nothingIsChosenAtFirst() async throws {
        // Arrange
        let choice = try makeChoice()

        // Act
        let availability = await choice.availability { _ in true }

        // Assert
        #expect(availability == .notChosen)
    }

    @Test
    func aChosenGitThatCanRunIsAvailable() async throws {
        // Arrange
        let choice = try makeChoice()
        let git = URL(filePath: "/opt/homebrew/bin/git")

        // Act
        choice.executableURL = git
        let availability = await choice.availability { _ in true }

        // Assert
        #expect(availability == .available(git))
    }

    @Test
    func aChosenGitThatCantRunIsMissingAndStaysChosen() async throws {
        // Arrange
        let choice = try makeChoice()
        let git = URL(filePath: "/opt/homebrew/bin/git")
        choice.executableURL = git

        // Act
        let availability = await choice.availability { _ in false }

        // Assert
        #expect(availability == .missing(git))
        #expect(choice.executableURL == git)
    }
}
