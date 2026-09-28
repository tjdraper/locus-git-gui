import Foundation
import Testing

struct ConflictVersionChoiceTests {
    private static func deletedByFeature() async throws -> FixtureRepository {
        let repository = try await FixtureRepository.make()
        try await repository.commit("Base", writing: "a\n", to: "notes.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.git("rm", "--quiet", "notes.txt")
        try await repository.git("commit", "--quiet", "--message", "Delete")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Main", writing: "main\n", to: "notes.txt")
        _ = try await repository.run(.changing(["merge", "--no-edit", "feature"]))
        return repository
    }

    private static func choose(_ choice: ConflictVersionChoice, _ path: String, in repository: FixtureRepository) async throws {
        let contents = try await repository.conflictContents(path)
        for command in choice.commands(for: path, stages: contents.stages) {
            let result = try await repository.run(command)
            guard result.status == 0 else { throw FixtureRepository.GitFailed(arguments: command.arguments, result: result) }
        }
    }

    @Test
    func keepingTheChangedVersionResolvesIt() async throws {
        // Arrange
        let repository = try await Self.deletedByFeature()
        defer { repository.remove() }

        // Act
        try await Self.choose(.ours, "notes.txt", in: repository)

        // Assert
        #expect(try await repository.status().files.isEmpty)
        #expect(try repository.contents(of: "notes.txt") == "main\n")
    }

    @Test
    func deletingResolvesIt() async throws {
        // Arrange
        let repository = try await Self.deletedByFeature()
        defer { repository.remove() }

        // Act
        try await Self.choose(.delete, "notes.txt", in: repository)

        // Assert
        let status = try await repository.status()
        #expect(status.files.map(\.state) == [.changed(staged: .deleted, unstaged: nil)])
        #expect(!FileManager.default.fileExists(atPath: repository.folder.appending(path: "notes.txt").path))
    }

    @Test
    func takingTheirVersionOfABinaryFileResolvesIt() async throws {
        // Arrange
        let repository = try await FixtureRepository.mergeStoppedOnConflict(
            path: "image.bin",
            base: "a\0",
            main: "main\0",
            feature: "feature\0"
        )
        defer { repository.remove() }

        // Act
        try await Self.choose(.theirs, "image.bin", in: repository)

        // Assert
        let status = try await repository.status()
        #expect(status.files.map(\.state) == [.changed(staged: .modified, unstaged: nil)])
        #expect(try repository.contents(of: "image.bin") == "feature\0")
    }
}
