import Foundation
import Testing

struct RemoteNameTests {
    @Test
    func listsEveryRemoteIncludingOnesNeverFetched() async throws {
        // Arrange
        let origin = try await FixtureRepository.make()
        defer { origin.remove() }
        try await origin.commit("First", writing: "a", to: "a.txt")
        let clone = try await origin.clone()
        defer { clone.remove() }
        try await clone.git("remote", "add", "upstream", "https://example.com/upstream.git")

        // Act
        let result = try await clone.run(RemoteName.listCommand)

        // Assert
        #expect(try RemoteName.parseList(result.standardOutput) == ["origin", "upstream"])
    }

    @Test
    func aRepositoryWithoutRemotesListsNone() throws {
        // Act
        let names = try RemoteName.parseList(Data())

        // Assert
        #expect(names.isEmpty)
    }
}
