import Foundation
import Testing

struct HistoryOperationCommandTests {
    /// `main` and `feature` both change `a.txt` after their shared first commit.
    private func divergedRepository() async throws -> FixtureRepository {
        let repository = try await FixtureRepository.make()
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Feature", writing: "feature", to: "a.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Main", writing: "main", to: "a.txt")
        return repository
    }

    @Test
    func aMergeThatConflictsStopsAndIsFinishedByContinuing() async throws {
        // Arrange
        let repository = try await divergedRepository()
        defer { repository.remove() }

        // Act
        let merged = try await repository.run(HistoryOperationCommand.merge("feature"))
        let operation = InProgressOperation.read(gitDirectory: repository.folder.appending(path: ".git"))
        try repository.write("both", to: "a.txt")
        try await repository.git("add", "a.txt")
        let continued = try await repository.run(HistoryOperationCommand.continueOperation(.merge))

        // Assert
        #expect(RecognizedGitFailure.recognize(merged) == .stoppedOnConflicts)
        #expect(operation == .merging)
        #expect(continued.status == 0)
        #expect(try await repository.git("log", "-1", "--format=%s") == "Merge branch 'feature'")
    }

    @Test
    func continuingWithConflictsLeftIsRecognized() async throws {
        // Arrange
        let repository = try await divergedRepository()
        defer { repository.remove() }
        _ = try await repository.run(HistoryOperationCommand.merge("feature"))

        // Act
        let continued = try await repository.run(HistoryOperationCommand.continueOperation(.merge))

        // Assert
        #expect(RecognizedGitFailure.recognize(continued) == .unresolvedConflicts)
    }

    @Test
    func aRebaseThatConflictsIsSkippedOrAborted() async throws {
        // Arrange
        let repository = try await divergedRepository()
        defer { repository.remove() }
        let before = try await repository.git("rev-parse", "main")

        // Act
        let rebased = try await repository.run(HistoryOperationCommand.rebase(onto: "feature"))
        let aborted = try await repository.run(HistoryOperationCommand.abort(.rebase))
        let rebasedAgain = try await repository.run(HistoryOperationCommand.rebase(onto: "feature"))
        let skipped = try await repository.run(try #require(HistoryOperationCommand.skip(.rebase)))

        // Assert
        #expect(RecognizedGitFailure.recognize(rebased) == .stoppedOnConflicts)
        #expect(aborted.status == 0)
        #expect(RecognizedGitFailure.recognize(rebasedAgain) == .stoppedOnConflicts)
        #expect(skipped.status == 0)
        #expect(try await repository.git("rev-parse", "main") == repository.git("rev-parse", "feature"))
        #expect(before != (try await repository.git("rev-parse", "main")))
    }

    @Test
    func aBranchThatIsNotCheckedOutIsRebased() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("branch", "feature")
        try await repository.commit("Second", writing: "b", to: "b.txt")
        try await repository.git("switch", "--quiet", "feature")
        try await repository.commit("Feature", writing: "c", to: "c.txt")
        try await repository.git("switch", "--quiet", "main")

        // Act
        let result = try await repository.run(HistoryOperationCommand.rebase(onto: "main", branch: "feature"))

        // Assert
        #expect(result.status == 0)
        #expect(try await repository.git("branch", "--show-current") == "feature")
        #expect(try await repository.git("rev-parse", "feature~1") == repository.git("rev-parse", "main"))
    }

    @Test
    func aMergeBlockedByLocalChangesGoesAheadWithAutostash() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Feature", writing: "feature", to: "a.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Other", writing: "b", to: "b.txt")
        try repository.write("local", to: "b.txt")
        try repository.write("local", to: "a.txt")

        // Act
        let blocked = try await repository.run(HistoryOperationCommand.merge("feature"))
        try repository.write("b", to: "b.txt")
        try await repository.git("checkout", "--", "a.txt")
        try repository.write("local", to: "b.txt")
        let merged = try await repository.run(HistoryOperationCommand.merge("feature", autostash: true))

        // Assert
        #expect(RecognizedGitFailure.recognize(blocked) == .localChangesWouldBeOverwritten(files: ["a.txt"], includesUntracked: false))
        #expect(merged.status == 0)
        #expect(try String(contentsOf: repository.folder.appending(path: "b.txt"), encoding: .utf8) == "local")
        #expect(try await repository.git("stash", "list").isEmpty)
    }

    @Test
    func aCommitIsCherryPickedAndReverted() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Feature", writing: "b", to: "b.txt")
        let feature = try await repository.git("rev-parse", "HEAD")
        try await repository.git("switch", "--quiet", "main")

        // Act
        let picked = try await repository.run(HistoryOperationCommand.cherryPick(feature, isMerge: false))
        let reverted = try await repository.run(HistoryOperationCommand.revert("HEAD", isMerge: false))

        // Assert
        #expect(picked.status == 0)
        #expect(reverted.status == 0)
        #expect(try await repository.git("log", "--format=%s") == "Revert \"Feature\"\nFeature\nFirst")
        #expect(!FileManager.default.fileExists(atPath: repository.folder.appending(path: "b.txt").path))
    }

    @Test(arguments: HistoryOperationCommand.ResetMode.allCases)
    func resetMovesTheBranchAndKeepsChangesAsTheModeSays(mode: HistoryOperationCommand.ResetMode) async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.commit("Second", writing: "b", to: "b.txt")

        // Act
        let result = try await repository.run(HistoryOperationCommand.reset(to: "HEAD~1", mode: mode))

        // Assert
        #expect(result.status == 0)
        #expect(try await repository.git("log", "--format=%s") == "First")
        let status = try await repository.git("status", "--porcelain")
        switch mode {
        case .soft: #expect(status == "A  b.txt")
        case .mixed: #expect(status == "?? b.txt")
        case .hard: #expect(status.isEmpty)
        }
    }

    @Test
    func tellsWhetherACommitIsInABranchsHistory() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Feature", writing: "b", to: "b.txt")

        // Act
        let first = try await repository.run(HistoryOperationCommand.isAncestor("HEAD~1", of: "main"))
        let feature = try await repository.run(HistoryOperationCommand.isAncestor("HEAD", of: "main"))

        // Assert
        #expect(first.status == 0)
        #expect(feature.status == 1)
    }
}

struct MergeCountTests {
    @Test
    func countsTheMergesAfterACommit() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("One", writing: "1", to: "one.txt")
        let one = try await repository.git("rev-parse", "HEAD")
        try await repository.git("switch", "--quiet", "--create", "side")
        try await repository.commit("Side", writing: "s", to: "side.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Two", writing: "2", to: "two.txt")
        try await repository.git("merge", "--quiet", "--no-edit", "side")

        // Act
        let afterOne = try await repository.run(HistoryOperationCommand.mergeCount(after: one))
        let afterHead = try await repository.run(HistoryOperationCommand.mergeCount(after: "HEAD"))

        // Assert
        #expect(String(bytes: afterOne.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        #expect(String(bytes: afterHead.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }
}
