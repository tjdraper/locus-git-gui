import Foundation
import Testing

struct RepositoryResolverTests {
    private let runner = GitRunner(executableURL: TestGit.executableURL, environment: FixtureRepository.environment)

    private func expected(for repository: FixtureRepository) -> Repository {
        Repository(
            workTree: URL(filePath: repository.folder.path, directoryHint: .isDirectory),
            gitDirectory: URL(filePath: repository.folder.path + "/.git", directoryHint: .isDirectory)
        )
    }

    @Test
    func aSubfolderResolvesToTheTopLevel() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        let subfolder = repository.folder.appending(path: "Sources/Deep", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        // Act
        let fromTop = try await RepositoryResolver.resolve(repository.folder, with: runner)
        let fromSubfolder = try await RepositoryResolver.resolve(subfolder, with: runner)

        // Assert
        #expect(fromTop == .repository(expected(for: repository)))
        #expect(fromSubfolder == fromTop)
    }

    @Test
    func theGitDirectoryResolvesToItsWorkTree() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        let objects = repository.folder.appending(path: ".git/objects", directoryHint: .isDirectory)

        // Act
        let resolution = try await RepositoryResolver.resolve(objects, with: runner)

        // Assert
        #expect(resolution == .repository(expected(for: repository)))
    }

    @Test
    func aBareRepositoryIsRecognized() async throws {
        // Arrange
        let folder = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await runner.run(.changing(["init", "--quiet", "--bare"]), in: folder)

        // Act
        let resolution = try await RepositoryResolver.resolve(folder, with: runner)

        // Assert
        #expect(resolution == .bare)
    }

    @Test
    func aPlainFolderIsNotARepository() async throws {
        // Arrange
        let folder = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Act
        let resolution = try await RepositoryResolver.resolve(folder, with: runner)

        // Assert
        #expect(resolution == .notRepository)
    }

    @Test
    func aPrivacyDenialIsRecognized() {
        // Arrange
        let result = ChildProcess.Result(
            status: 128,
            standardOutput: Data(),
            standardError: Data("fatal: Unable to read current working directory: Operation not permitted\n".utf8)
        )

        // Act
        let answer = RepositoryResolver.interpret(result)

        // Assert
        #expect(answer == .resolved(.accessDenied))
    }

    @Test
    func anythingElseKeepsGitsExplanation() {
        // Arrange
        let result = ChildProcess.Result(
            status: 128,
            standardOutput: Data(),
            standardError: Data("fatal: detected dubious ownership in repository at '/Volumes/Drive/repo'\n".utf8)
        )

        // Act
        let answer = RepositoryResolver.interpret(result)

        // Assert
        #expect(answer == .resolved(.failed("fatal: detected dubious ownership in repository at '/Volumes/Drive/repo'")))
    }
}
