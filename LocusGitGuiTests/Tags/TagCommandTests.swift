import Foundation
import Testing

struct TagCommandTests {
    @Test
    func aTagWithAMessageIsAnnotated() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")

        // Act
        let annotated = try await repository.run(TagCommand.create("v1", at: "HEAD", message: "Release"))
        let lightweight = try await repository.run(TagCommand.create("v2", at: "HEAD", message: ""))

        // Assert
        #expect(annotated.status == 0)
        #expect(lightweight.status == 0)
        #expect(try await repository.git("cat-file", "-t", "v1") == "tag")
        #expect(try await repository.git("cat-file", "-t", "v2") == "commit")
    }

    @Test
    func aTagIsDeleted() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("tag", "v1")

        // Act
        let result = try await repository.run(TagCommand.delete("v1"))

        // Assert
        #expect(result.status == 0)
        #expect(try await repository.git("tag", "--list").isEmpty)
    }
}
