import Foundation
import Testing

struct CommitRewriteTests {
    private func threeCommits() async throws -> FixtureRepository {
        let repository = try await FixtureRepository.make()
        try await repository.commit("One", writing: "1", to: "one.txt")
        try await repository.commit("Two", writing: "2", to: "two.txt")
        try await repository.commit("Three", writing: "3", to: "three.txt")
        return repository
    }

    @Test
    func stopsAtTheCommitAndAmendsWhatIsStagedWhenContinued() async throws {
        // Arrange
        let repository = try await threeCommits()
        defer { repository.remove() }
        let two = try await repository.git("rev-parse", "HEAD~1")

        // Act
        let started = try await repository.run(CommitRewrite.start(marking: two, parent: "\(two)~1"))
        let stoppedAt = try await repository.git("rev-parse", "HEAD")
        let operation = InProgressOperation.read(gitDirectory: repository.folder.appending(path: ".git"))
        try repository.write("edited", to: "two.txt")
        try await repository.git("add", "two.txt")
        let continued = try await repository.run(HistoryOperationCommand.continueOperation(.rebase))

        // Assert
        #expect(started.status == 0)
        #expect(stoppedAt == two)
        // Git counts the lines `--rebase-merges` adds to the list, such as its labels.
        #expect(operation == .rebasing(branch: "main", step: 3, total: 4))
        #expect(continued.status == 0)
        #expect(try await repository.git("log", "--format=%s") == "Three\nTwo\nOne")
        #expect(try await repository.git("show", "HEAD~1:two.txt") == "edited")
    }

    @Test
    func rewordsTheFirstCommit() async throws {
        // Arrange
        let repository = try await threeCommits()
        defer { repository.remove() }
        let one = try await repository.git("rev-parse", "HEAD~2")

        // Act
        let started = try await repository.run(CommitRewrite.start(marking: one, parent: nil))
        let reworded = try await repository.run(CommitRewrite.reword(message: "Uno\n\nThe first."))
        let continued = try await repository.run(HistoryOperationCommand.continueOperation(.rebase))

        // Assert
        #expect(started.status == 0)
        #expect(reworded.status == 0)
        #expect(continued.status == 0)
        #expect(try await repository.git("log", "--format=%s") == "Three\nTwo\nUno")
        #expect(try await repository.git("log", "-1", "--format=%b", "HEAD~2") == "The first.")
    }

    @Test
    func keepsAMergeAfterTheCommit() async throws {
        // Arrange
        let repository = try await threeCommits()
        defer { repository.remove() }
        try await repository.git("switch", "--quiet", "--create", "side", "HEAD~1")
        try await repository.commit("Side", writing: "s", to: "side.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.git("merge", "--quiet", "--no-edit", "--no-ff", "side")
        let one = try await repository.git("rev-list", "--max-parents=0", "HEAD")

        // Act
        _ = try await repository.run(CommitRewrite.start(marking: one, parent: nil))
        _ = try await repository.run(CommitRewrite.reword(message: "Uno"))
        let continued = try await repository.run(HistoryOperationCommand.continueOperation(.rebase))

        // Assert
        #expect(continued.status == 0)
        #expect(try await repository.git("rev-list", "--merges", "--count", "HEAD") == "1")
        #expect(try await repository.git("log", "--format=%s", "--reverse").hasPrefix("Uno\n"))
    }
}
