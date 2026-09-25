import Foundation
import Testing

struct RecentRepositoryStateTests {
    private func recorded(_ repository: FixtureRepository) -> Repository {
        Repository(
            workTree: URL(filePath: repository.folder.path, directoryHint: .isDirectory),
            gitDirectory: URL(filePath: repository.folder.path + "/.git", directoryHint: .isDirectory)
        )
    }

    private func state(of repository: FixtureRepository) async throws -> RecentRepositoryState {
        try await RecentRepositoryState.read(recorded(repository)) { try await repository.run($0) }
    }

    @Test
    func aRepositoryIsOnItsCheckedOutBranch() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("switch", "--quiet", "--create", "feature/login")

        // Act
        let state = try await state(of: repository)

        // Assert
        #expect(state == .onBranch("feature/login"))
    }

    @Test
    func aRepositoryWithNoCommitsIsOnItsFirstBranch() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }

        // Act
        let state = try await state(of: repository)

        // Assert
        #expect(state == .onBranch("main"))
    }

    @Test
    func aDetachedHeadNamesItsCommit() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        let commit = try await repository.git("rev-parse", "--short", "HEAD")
        try await repository.git("switch", "--quiet", "--detach")

        // Act
        let state = try await state(of: repository)

        // Assert
        #expect(state == .detached(commit: commit))
    }

    @Test
    func aStoppedRebaseIsOnTheBranchBeingRebased() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Base", writing: "base", to: "shared.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Feature", writing: "feature", to: "shared.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Main", writing: "main", to: "shared.txt")
        try await repository.git("switch", "--quiet", "feature")
        _ = try await repository.run(.changing(["rebase", "main"]))

        // Act
        let state = try await state(of: repository)

        // Assert
        #expect(state == .onBranch("feature"))
    }

    @Test
    func aDeletedRepositoryIsMissing() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        repository.remove()

        // Act
        let state = try await state(of: repository)

        // Assert
        #expect(state == .missing)
    }

    @Test
    func aFolderThatIsNoLongerARepositoryIsMissing() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try FileManager.default.removeItem(at: repository.folder.appending(path: ".git"))

        // Act
        let state = try await state(of: repository)

        // Assert
        #expect(state == .missing)
    }

    @Test
    func aFolderNowInsideAnotherRepositoryIsMissing() async throws {
        // Arrange
        let outer = try await FixtureRepository.make()
        defer { outer.remove() }
        let inner = FixtureRepository(folder: outer.folder.appending(path: "inner", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: inner.folder, withIntermediateDirectories: true)
        try await inner.git("init", "--quiet")
        try FileManager.default.removeItem(at: inner.folder.appending(path: ".git"))

        // Act
        let state = try await state(of: inner)

        // Assert
        #expect(state == .missing)
    }
}
