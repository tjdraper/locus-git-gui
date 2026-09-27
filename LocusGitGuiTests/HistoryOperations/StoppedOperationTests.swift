import Foundation
import Testing

struct StoppedOperationTests {
    @Test
    func aMergeWithConflictsSaysHowManyFilesHaveThem() throws {
        // Act
        let stopped = try #require(StoppedOperation(.merging, branch: "main", conflicts: 2, editing: nil))

        // Assert
        #expect(stopped.kind == .merge)
        #expect(stopped.title == "Merging into “main”")
        #expect(stopped.detail == "2 files have conflicts. Resolve and stage each one, then Continue.")
    }

    @Test
    func aRebaseNamesItsBranchAndStep() throws {
        // Act
        let operation = InProgressOperation.rebasing(branch: "feature", step: 2, total: 5)
        let stopped = try #require(StoppedOperation(operation, branch: nil, conflicts: 0, editing: nil))

        // Assert
        #expect(stopped.title == "Rebasing “feature”, 2 of 5")
        #expect(stopped.detail == "Every conflict is resolved. Continue carries on with the commits after it.")
    }

    @Test
    func anEditSaysWhereItStopped() throws {
        // Act
        let stopped = try #require(StoppedOperation(
            .rebasing(branch: "main", step: 3, total: 4),
            branch: nil,
            conflicts: 0,
            editing: "305d367aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ))

        // Assert
        #expect(stopped.detail == "Stopped at 305d367 to edit it. Change it and stage the changes, then Continue.")
    }

    @Test
    func nothingHasStoppedWithoutAnOperationOrDuringABisect() {
        // Act
        let none = StoppedOperation(nil, branch: "main", conflicts: 0, editing: nil)
        let bisect = StoppedOperation(.bisecting, branch: "main", conflicts: 0, editing: nil)

        // Assert
        #expect(none == nil)
        #expect(bisect == nil)
    }

    @Test
    func findsTheCommitAnEditStoppedAt() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("One", writing: "1", to: "one.txt")
        try await repository.commit("Two", writing: "2", to: "two.txt")
        let one = try await repository.git("rev-parse", "HEAD~1")
        _ = try await repository.run(CommitRewrite.start(marking: one, parent: nil))

        // Act
        let editing = StoppedOperation.editedCommit(gitDirectory: repository.folder.appending(path: ".git"))

        // Assert
        #expect(editing == one)
    }
}
