import Foundation
import Testing

struct StashTests {
    private func stashes(of repository: FixtureRepository) async throws -> [Stash] {
        let result = try await repository.run(Stash.listCommand)
        #expect(result.status == 0)
        return try Stash.parseList(result.standardOutput)
    }

    @Test
    func listsNewestFirstWithGitsMessages() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("one", to: "a.txt")
        try await repository.git("stash", "--quiet")
        let older = try await repository.git("rev-parse", "stash@{0}")
        try repository.write("two", to: "a.txt")
        try await repository.git("stash", "push", "--quiet", "--message", "Half-done login form")
        let newer = try await repository.git("rev-parse", "stash@{0}")

        // Act
        let stashes = try await stashes(of: repository)

        // Assert
        #expect(stashes.map(\.commit) == [newer, older])
        #expect(stashes.first?.message == "On main: Half-done login form")
        #expect(stashes.last?.message.hasPrefix("WIP on main: ") == true)
    }

    @Test
    func aRepositoryWithoutStashesListsNone() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")

        // Act
        let stashes = try await stashes(of: repository)

        // Assert
        #expect(stashes.isEmpty)
    }
}
