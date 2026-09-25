import Foundation
import Testing

struct RepositorySnapshotTests {
    private let runner = GitRunner(executableURL: TestGit.executableURL, environment: FixtureRepository.environment)

    @Test
    func readsStatusAndOperationTogether() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("changed", to: "a.txt")
        let opened = Repository(workTree: repository.folder, gitDirectory: repository.folder.appending(path: ".git"))

        // Act
        let snapshot = try await RepositorySnapshot.read(opened) { try await runner.run($0, in: repository.folder) }

        // Assert
        #expect(snapshot.status.branch.name == "main")
        #expect(snapshot.status.files.map(\.path) == ["a.txt"])
        #expect(snapshot.operation == nil)
    }

    @Test
    func aFailedStatusKeepsGitsOutput() async throws {
        // Arrange
        let folder = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notARepository = Repository(workTree: folder, gitDirectory: folder.appending(path: ".git"))

        // Act & Assert
        let failure = await #expect(throws: GitReadFailure.self) {
            try await RepositorySnapshot.read(notARepository) { try await runner.run($0, in: folder) }
        }
        #expect(failure?.result.status == 128)
        #expect(String(bytes: failure?.result.standardError ?? Data(), encoding: .utf8)?.contains("not a git repository") == true)
    }
}
