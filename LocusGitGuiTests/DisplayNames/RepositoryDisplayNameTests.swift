import Foundation
import Testing

struct RepositoryDisplayNameTests {
    private func contents(of path: String, in repository: FixtureRepository) -> String? {
        try? String(contentsOf: repository.folder.appending(path: path), encoding: .utf8)
    }

    @Test
    func aRepositoryWithoutOneHasNoNameAndStartsOutShared() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }

        // Act
        let displayName = RepositoryDisplayName.read(from: repository.folder)

        // Assert
        #expect(displayName == RepositoryDisplayName(name: nil, isShared: true))
    }

    @Test
    func aNameNotSharedIsReadBack() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }

        // Act
        try RepositoryDisplayName(name: "  Marketing Site\n", isShared: false).write(to: repository.folder)
        let displayName = RepositoryDisplayName.read(from: repository.folder)

        // Assert
        #expect(displayName == RepositoryDisplayName(name: "Marketing Site", isShared: false))
        #expect(contents(of: ".locus/.name", in: repository) == "Marketing Site\n")
    }

    @Test
    func aNameNotSharedIsIgnoredByGit() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }

        // Act
        try RepositoryDisplayName(name: "Marketing Site", isShared: false).write(to: repository.folder)
        let status = try await repository.git("status", "--porcelain", "--untracked-files=all")

        // Assert
        #expect(status.isEmpty)
    }

    @Test
    func aSharedNameIsLeftForGitToTrack() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }

        // Act
        try RepositoryDisplayName(name: "Marketing Site", isShared: true).write(to: repository.folder)
        let status = try await repository.git("status", "--porcelain", "--untracked-files=all")

        // Assert
        #expect(status == "?? .locus/.name")
        #expect(RepositoryDisplayName.read(from: repository.folder) == RepositoryDisplayName(name: "Marketing Site", isShared: true))
    }

    @Test
    func sharingANameRemovesTheIgnoreFile() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try RepositoryDisplayName(name: "Marketing Site", isShared: false).write(to: repository.folder)

        // Act
        try RepositoryDisplayName(name: "Marketing Site", isShared: true).write(to: repository.folder)

        // Assert
        #expect(contents(of: ".locus/.gitignore", in: repository) == nil)
    }

    @Test
    func clearingTheNameRemovesTheFolder() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try RepositoryDisplayName(name: "Marketing Site", isShared: false).write(to: repository.folder)

        // Act
        try RepositoryDisplayName(name: " ", isShared: false).write(to: repository.folder)

        // Assert
        #expect(!FileManager.default.fileExists(atPath: repository.folder.appending(path: ".locus").path))
    }

    @Test
    func leavesAnIgnoreFileWrittenByHand() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("notes.txt\n", to: ".locus/.gitignore")

        // Act
        try RepositoryDisplayName(name: "Marketing Site", isShared: true).write(to: repository.folder)

        // Assert
        #expect(contents(of: ".locus/.gitignore", in: repository) == "notes.txt\n")
    }

    @Test
    func aCommittedNameIsTracked() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try RepositoryDisplayName(name: "Marketing Site", isShared: true).write(to: repository.folder)
        let untracked = try await repository.run(RepositoryDisplayName.trackedFilesCommand)
        try await repository.git("add", "--", ".locus")
        try await repository.git("commit", "--quiet", "--message", "Name the repository")

        // Act
        let tracked = try await repository.run(RepositoryDisplayName.trackedFilesCommand)

        // Assert
        #expect(!RepositoryDisplayName.isTracked(untracked))
        #expect(RepositoryDisplayName.isTracked(tracked))
    }
}
