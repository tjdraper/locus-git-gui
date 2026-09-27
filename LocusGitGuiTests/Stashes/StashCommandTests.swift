import Foundation
import Testing

struct StashCommandTests {
    @Test
    func stashesUntrackedFilesOnlyWhenAsked() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("changed", to: "a.txt")
        try repository.write("new", to: "new.txt")

        // Act
        let tracked = try await repository.run(StashCommand.stash(message: "Tracked", includingUntracked: false))
        let statusAfterTracked = try await repository.git("status", "--porcelain")
        let untracked = try await repository.run(StashCommand.stash(message: "", includingUntracked: true))

        // Assert
        #expect(tracked.status == 0)
        #expect(statusAfterTracked == "?? new.txt")
        #expect(untracked.status == 0)
        #expect(try await repository.git("status", "--porcelain").isEmpty)
        #expect(try await repository.git("stash", "list", "--format=%gs").hasSuffix("On main: Tracked"))
    }

    @Test
    func popsAndDropsByPlaceFoundFromTheCommit() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("older", to: "a.txt")
        try await repository.git("stash", "push", "--quiet", "--message", "Older")
        let older = try await repository.git("rev-parse", "stash@{0}")
        try repository.write("newer", to: "a.txt")
        try await repository.git("stash", "push", "--quiet", "--message", "Newer")

        // Act
        let index = try await StashCommand.index(of: older) { try await repository.run($0) }
        let popped = try await repository.run(StashCommand.pop(at: index ?? -1))

        // Assert
        #expect(index == 1)
        #expect(popped.status == 0)
        #expect(try String(contentsOf: repository.folder.appending(path: "a.txt"), encoding: .utf8) == "older")
        #expect(try await repository.git("stash", "list", "--format=%gs") == "On main: Newer")
    }

    @Test
    func aDroppedStashIsStoredBack() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("changed", to: "a.txt")
        try await repository.git("stash", "push", "--quiet", "--message", "Kept")
        let commit = try await repository.git("rev-parse", "stash@{0}")

        // Act
        let dropped = try await repository.run(StashCommand.drop(at: 0))
        let stored = try await repository.run(StashCommand.store(commit, message: "On main: Kept"))

        // Assert
        #expect(dropped.status == 0)
        #expect(stored.status == 0)
        #expect(try await repository.git("rev-parse", "stash@{0}") == commit)
    }

    @Test
    func aConflictingPopIsRecognizedAndKeepsTheStash() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("stashed", to: "a.txt")
        try await repository.git("stash", "push", "--quiet")
        try await repository.commit("Second", writing: "committed", to: "a.txt")

        // Act
        let command = StashCommand.pop(at: 0)
        let result = try await repository.run(command)

        // Assert
        #expect(RecognizedGitFailure.recognize(result, arguments: command.arguments) == .stashConflicts)
        #expect(try await repository.git("stash", "list").isEmpty == false)
    }
}
