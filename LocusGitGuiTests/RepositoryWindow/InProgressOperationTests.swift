import Foundation
import Testing

struct InProgressOperationTests {
    private func operation(in repository: FixtureRepository) -> InProgressOperation? {
        InProgressOperation.read(gitDirectory: repository.folder.appending(path: ".git"))
    }

    /// `main` and `feature` both change `shared.txt` after `Base`, so combining them stops on a conflict.
    private func makeDivergedRepository() async throws -> FixtureRepository {
        let repository = try await FixtureRepository.make()
        try await repository.commit("Base", writing: "base", to: "shared.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Theirs", writing: "theirs", to: "shared.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Ours", writing: "ours", to: "shared.txt")
        return repository
    }

    /// Three commits on `feature`, of which only the second conflicts with `main`.
    private func makeRebaseThatStopsOnTheSecondCommit() async throws -> FixtureRepository {
        let repository = try await FixtureRepository.make()
        try await repository.commit("Base", writing: "base", to: "shared.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("One", writing: "one", to: "one.txt")
        try await repository.commit("Two", writing: "feature", to: "shared.txt")
        try await repository.commit("Three", writing: "three", to: "three.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Main", writing: "main", to: "shared.txt")
        try await repository.git("switch", "--quiet", "feature")
        return repository
    }

    @Test
    func aCleanRepositoryHasNothingInProgress() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")

        // Act
        let operation = operation(in: repository)

        // Assert
        #expect(operation == nil)
    }

    @Test
    func aStoppedMergeIsMerging() async throws {
        // Arrange
        let repository = try await makeDivergedRepository()
        defer { repository.remove() }
        _ = try await repository.run(.changing(["merge", "feature"]))

        // Act
        let operation = operation(in: repository)

        // Assert
        #expect(operation == .merging)
    }

    @Test(arguments: [[String](), ["--apply"]])
    func aStoppedRebaseKnowsItsBranchAndStep(backend: [String]) async throws {
        // Arrange
        let repository = try await makeRebaseThatStopsOnTheSecondCommit()
        defer { repository.remove() }
        _ = try await repository.run(.changing(["rebase"] + backend + ["main"]))

        // Act
        let operation = operation(in: repository)

        // Assert
        #expect(operation == .rebasing(branch: "feature", step: 2, total: 3))
    }

    @Test
    func aStoppedCherryPickIsCherryPicking() async throws {
        // Arrange
        let repository = try await makeDivergedRepository()
        defer { repository.remove() }
        _ = try await repository.run(.changing(["cherry-pick", "feature"]))

        // Act
        let operation = operation(in: repository)

        // Assert
        #expect(operation == .cherryPicking)
    }

    @Test
    func aStoppedRevertIsReverting() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Base", writing: "base", to: "shared.txt")
        try await repository.commit("Change", writing: "changed", to: "shared.txt")
        try await repository.commit("Change again", writing: "changed again", to: "shared.txt")
        _ = try await repository.run(.changing(["revert", "--no-edit", "HEAD~1"]))

        // Act
        let operation = operation(in: repository)

        // Assert
        #expect(operation == .reverting)
    }

    @Test
    func aBisectIsBisecting() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("bisect", "start")

        // Act
        let operation = operation(in: repository)

        // Assert
        #expect(operation == .bisecting)
    }
}
