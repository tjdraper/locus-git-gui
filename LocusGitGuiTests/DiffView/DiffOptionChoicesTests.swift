import Foundation
import Testing

struct DiffOptionChoicesTests {
    @Test
    func onlyWhatDiffersFromTheDefaultsIsAChoice() {
        // Arrange
        let defaults = DiffOptions(ignoresWhitespace: true, contextLines: 3)

        // Act
        let choices = DiffOptionChoices(DiffOptions(ignoresWhitespace: true, contextLines: 10), defaults: defaults)

        // Assert
        #expect(choices == DiffOptionChoices(contextLines: 10))
    }

    @Test
    func whatWasNotChosenFollowsTheDefaults() {
        // Arrange
        let choices = DiffOptionChoices(contextLines: 10)

        // Act
        let before = choices.applied(to: DiffOptions(ignoresWhitespace: false, contextLines: 3))
        let after = choices.applied(to: DiffOptions(ignoresWhitespace: true, contextLines: 5))

        // Assert
        #expect(before == DiffOptions(ignoresWhitespace: false, contextLines: 10))
        #expect(after == DiffOptions(ignoresWhitespace: true, contextLines: 10))
    }

    @Test
    func anOptionSetBackToTheDefaultFollowsItAgain() {
        // Arrange
        let defaults = DiffOptions()
        var options = DiffOptionChoices(ignoresWhitespace: true).applied(to: defaults)

        // Act
        options.ignoresWhitespace = false
        let choices = DiffOptionChoices(options, defaults: defaults)

        // Assert
        #expect(choices == DiffOptionChoices())
    }
}
