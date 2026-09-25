import Foundation
import Testing

struct GitLockRecoveryTests {
    private func opened(_ repository: FixtureRepository) -> Repository {
        Repository(workTree: repository.folder, gitDirectory: repository.folder.appending(path: ".git"))
    }

    @Test
    func anAbandonedLockCanBeRemoved() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("", to: ".git/index.lock")
        let lock = repository.folder.appending(path: ".git/index.lock")

        // Act
        let before = GitLockRecovery.state(of: lock, in: opened(repository))
        try GitLockRecovery.remove(lock, in: opened(repository))

        // Assert
        guard case .abandoned = before else {
            Issue.record("Expected an abandoned lock, got \(before)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: lock.path))
        #expect(GitLockRecovery.state(of: lock, in: opened(repository)) == .gone)
    }

    @Test
    func aLockIsKeptWhileGitRunsInTheRepository() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("", to: ".git/index.lock")
        let lock = repository.folder.appending(path: ".git/index.lock")
        let process = Process()
        process.executableURL = TestGit.executableURL
        process.arguments = ["cat-file", "--batch"]
        process.currentDirectoryURL = repository.folder
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
        }

        // Act & Assert
        #expect(GitLockRecovery.state(of: lock, in: opened(repository)) == .inUse(processes: [process.processIdentifier]))
        #expect(throws: GitLockRecovery.RemovalFailure.inUse) {
            try GitLockRecovery.remove(lock, in: opened(repository))
        }
        #expect(FileManager.default.fileExists(atPath: lock.path))
    }

    @Test
    func onlyLockFilesInsideTheRepositoryAreRemoved() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        let elsewhere = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        let outsideLock = elsewhere.appending(path: "index.lock")
        try "".write(to: outsideLock, atomically: true, encoding: .utf8)
        let notALock = repository.folder.appending(path: ".git/HEAD")

        // Act & Assert
        #expect(throws: GitLockRecovery.RemovalFailure.notALockInThisRepository) {
            try GitLockRecovery.remove(outsideLock, in: opened(repository))
        }
        #expect(throws: GitLockRecovery.RemovalFailure.notALockInThisRepository) {
            try GitLockRecovery.remove(notALock, in: opened(repository))
        }
        #expect(FileManager.default.fileExists(atPath: outsideLock.path))
        #expect(FileManager.default.fileExists(atPath: notALock.path))
    }
}
