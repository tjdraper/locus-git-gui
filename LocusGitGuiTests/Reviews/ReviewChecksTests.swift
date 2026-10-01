import Foundation
import Testing

struct ReviewChecksTests {
    private func file(_ path: String, _ newObject: String) -> ReviewedFile {
        ReviewedFile(path: path, oldMode: "100644", newMode: "100644", oldObject: "old", newObject: newObject)
    }

    @Test
    func aFileChangedBackToHowItWasCheckedIsCheckedAgain() {
        // Arrange
        var checks = ReviewChecks()
        checks.check(file("a", "1"), at: Date())
        checks.follow([file("a", "2")])

        // Act
        checks.follow([file("a", "1")])

        // Assert
        #expect(checks.state(of: file("a", "1")) == .checked)
    }

    @Test
    func aFileThatLeavesTheReviewTakesItsCheckWithIt() {
        // Arrange
        var checks = ReviewChecks()
        checks.check(file("a", "1"), at: Date())

        // Act
        checks.follow([])
        checks.follow([file("a", "1")])

        // Assert
        #expect(checks.state(of: file("a", "1")) == .unchecked)
    }

    @Test
    func uncheckingByHandForgetsTheReviewedVersion() {
        // Arrange
        var checks = ReviewChecks()
        checks.check(file("a", "1"), at: Date())
        checks.follow([file("a", "2")])

        // Act
        checks.uncheck("a")

        // Assert
        #expect(checks.state(of: file("a", "2")) == .unchecked)
        #expect(checks.reviewedVersion(of: "a") == nil)
    }

    @Test
    func checkingAgainAfterAChangeReplacesTheReviewedVersion() {
        // Arrange
        var checks = ReviewChecks()
        checks.check(file("a", "1"), at: Date())
        checks.follow([file("a", "2")])

        // Act
        checks.check(file("a", "2"), at: Date())

        // Assert
        #expect(checks.state(of: file("a", "2")) == .checked)
        #expect(checks.reviewedVersion(of: "a") == nil)
        #expect(checks.keptObjects == ["old", "2"])
    }

    @Test
    func aSubmodulesCommitsArentKept() {
        // Arrange
        var checks = ReviewChecks()
        let submodule = ReviewedFile(path: "lib", oldMode: "160000", newMode: "160000", oldObject: "c1", newObject: "c2")

        // Act
        checks.check(submodule, at: Date())

        // Assert
        #expect(checks.keptObjects.isEmpty)
    }
}
