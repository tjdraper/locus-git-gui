import Foundation
import Testing

struct RecognizedGitFailureTests {
    @Test
    func aHeldIndexLockIsRecognizedWithItsPath() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("", to: ".git/index.lock")
        try repository.write("changed", to: "a.txt")

        // Act
        let result = try await repository.run(.changing(["add", "a.txt"]))

        // Assert
        #expect(RecognizedGitFailure.recognize(result) == .lockExists(repository.folder.appending(path: ".git/index.lock")))
    }

    @Test
    func aHeldRefLockIsRecognizedToo() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("", to: ".git/refs/heads/main.lock")
        try repository.write("changed", to: "a.txt")

        // Act
        let result = try await repository.run(.changing(["commit", "--quiet", "--all", "--message", "Second"]))

        // Assert
        #expect(RecognizedGitFailure.recognize(result) == .lockExists(repository.folder.appending(path: ".git/refs/heads/main.lock")))
    }

    @Test
    func anOrdinaryFailureIsNotRecognized() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }

        // Act
        let result = try await repository.run(.reading(["rev-parse", "--verify", "no-such-branch"]))

        // Assert
        #expect(result.status != 0)
        #expect(RecognizedGitFailure.recognize(result) == nil)
    }

    /// macOS privacy protection can't be set off from a test, so this is the system's wording as
    /// Git passes it on.
    @Test
    func aPrivacyDenialIsRecognized() {
        // Arrange
        let result = ChildProcess.Result(
            status: 128,
            standardOutput: Data(),
            standardError: Data("fatal: Unable to read current working directory: Operation not permitted\n".utf8)
        )

        // Act
        let recognized = RecognizedGitFailure.recognize(result)

        // Assert
        #expect(recognized == .accessDenied)
    }

    @Test
    func successIsNeverAFailure() {
        // Arrange
        let result = ChildProcess.Result(status: 0, standardOutput: Data("Operation not permitted".utf8), standardError: Data())

        // Act
        let recognized = RecognizedGitFailure.recognize(result)

        // Assert
        #expect(recognized == nil)
    }
}
