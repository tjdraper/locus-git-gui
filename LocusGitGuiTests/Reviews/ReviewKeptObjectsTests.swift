import Foundation
import Testing

struct ReviewKeptObjectsTests {
    @Test
    func keptContentsOutliveAForcePushAndGarbageCollection() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Start", writing: "one\n", to: "a.txt")
        try await repository.commit("Reviewed", writing: "reviewed\n", to: "a.txt")
        let reviewed = try await repository.git("rev-parse", "HEAD:a.txt")
        let id = UUID()

        // Act
        let tree = try await repository.run(ReviewKeptObjects.treeCommand([reviewed]))
        let hash = try #require(String(bytes: tree.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines))
        _ = try await repository.run(ReviewKeptObjects.pointCommand(for: id, at: hash))
        try await repository.git("reset", "--quiet", "--hard", "HEAD~1")
        try await repository.git("reflog", "expire", "--expire=now", "--all")
        try await repository.git("gc", "--quiet", "--prune=now")

        // Assert
        #expect(try await repository.git("cat-file", "-t", reviewed) == "blob")
        #expect(try await repository.git("log", "--all", "--format=%s") == "Start")
    }

    @Test
    func deletingTheRefLetsGitDeleteTheContents() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Start", writing: "one\n", to: "a.txt")
        let loose = try await repository.git("hash-object", "-w", "--stdin")
        let id = UUID()
        let tree = try await repository.run(ReviewKeptObjects.treeCommand([loose]))
        let hash = try #require(String(bytes: tree.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines))
        _ = try await repository.run(ReviewKeptObjects.pointCommand(for: id, at: hash))

        // Act
        _ = try await repository.run(ReviewKeptObjects.deleteCommand(for: id))

        // Assert
        let refs = try await repository.git("for-each-ref", ReviewKeptObjects.refPrefix)
        #expect(refs.isEmpty)
    }
}
