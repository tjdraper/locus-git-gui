import Foundation
import Testing

struct GitProcessFinderTests {
    /// `cat-file --batch` waits on its input, which stays open until the test closes it.
    private func startWaitingGit(in folder: URL) throws -> (Process, Pipe) {
        let process = Process()
        process.executableURL = TestGit.executableURL
        process.arguments = ["cat-file", "--batch"]
        process.currentDirectoryURL = folder
        process.environment = FixtureRepository.environment
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        return (process, input)
    }

    @Test
    func findsGitRunningInTheRepositoryAndNowhereElse() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        let elsewhere = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        let (process, input) = try startWaitingGit(in: repository.folder)
        defer {
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
        }

        // Act
        let inRepository = GitProcessFinder.processes(workingIn: [repository.folder])
        let inOtherFolder = GitProcessFinder.processes(workingIn: [elsewhere])

        // Assert
        #expect(inRepository.contains(process.processIdentifier))
        #expect(!inOtherFolder.contains(process.processIdentifier))
    }

    @Test
    func aFinishedGitIsNotFound() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        let (process, input) = try startWaitingGit(in: repository.folder)

        // Act
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let found = GitProcessFinder.processes(workingIn: [repository.folder])

        // Assert
        #expect(!found.contains(process.processIdentifier))
    }

    @Test
    func leavesOutTheProcessesAParentStarted() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        let (process, input) = try startWaitingGit(in: repository.folder)
        defer {
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
        }

        // Act
        let found = GitProcessFinder.processes(workingIn: [repository.folder], excludingChildrenOf: getpid())

        // Assert
        #expect(!found.contains(process.processIdentifier))
    }
}
