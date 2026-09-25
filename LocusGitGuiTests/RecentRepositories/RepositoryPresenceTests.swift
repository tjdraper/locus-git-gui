import Foundation
import Testing

struct RepositoryPresenceTests {
    private func repository(at folder: URL) -> Repository {
        Repository(workTree: folder, gitDirectory: folder.appending(path: ".git", directoryHint: .isDirectory))
    }

    @Test
    func aRepositoryInItsPlaceIsPresent() async throws {
        // Arrange
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }

        // Act
        let presence = RepositoryPresence.check(repository(at: fixture.folder))

        // Assert
        #expect(presence == .present)
    }

    @Test
    func aDeletedFolderIsMissing() throws {
        // Arrange
        let folder = try TestGit.makeScratchFolder()
        try FileManager.default.removeItem(at: folder)

        // Act
        let presence = RepositoryPresence.check(repository(at: folder))

        // Assert
        #expect(presence == .missing)
    }

    @Test
    func aFolderWhoseGitDirectoryIsGoneIsMissing() throws {
        // Arrange
        let folder = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Act
        let presence = RepositoryPresence.check(repository(at: folder))

        // Assert
        #expect(presence == .missing)
    }

    @Test
    func aFolderOnAnUnmountedDriveIsOnADriveNotConnected() {
        // Arrange
        let folder = URL(filePath: "/Volumes/LocusGitGuiTests-\(UUID().uuidString)/work/app", directoryHint: .isDirectory)

        // Act
        let presence = RepositoryPresence.check(repository(at: folder))

        // Assert
        #expect(presence == .driveNotConnected)
    }

    @Test
    func aDeletedFolderOnAConnectedDriveIsMissing() throws {
        // Arrange
        let drive = try #require(FileManager.default.contentsOfDirectory(atPath: "/Volumes").first)
        let folder = URL(filePath: "/Volumes/\(drive)/LocusGitGuiTests-\(UUID().uuidString)", directoryHint: .isDirectory)

        // Act
        let presence = RepositoryPresence.check(repository(at: folder))

        // Assert
        #expect(presence == .missing)
    }
}
