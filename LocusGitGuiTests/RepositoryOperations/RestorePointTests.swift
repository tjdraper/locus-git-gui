import Foundation
import Testing

struct RestorePointTests {
    @Test
    func readsTheCommitARefIsAt() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First line", writing: "a", to: "a.txt")
        let hash = try await repository.git("rev-parse", "HEAD")

        // Act
        let point = await RestorePoint.read("main") { try await repository.run($0) }

        // Assert
        #expect(point == RestorePoint(hash: hash, subject: "First line"))
        #expect(point?.described == "\(hash.prefix(7)) (“First line”)")
    }
}
