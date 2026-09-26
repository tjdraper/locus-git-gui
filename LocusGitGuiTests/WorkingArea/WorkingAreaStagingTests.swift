import Foundation
import Testing

struct WorkingAreaStagingTests {
    @Test
    func stagesAndUnstagesFilesByName() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        try repository.write("changed\n", to: "a.txt")
        try repository.write("new\n", to: "*.txt")

        // Act
        try await WorkingAreaStaging.stage(["*.txt"]) { try await repository.run($0) }
        let staged = WorkingAreaSummary(try await repository.status())
        try await WorkingAreaStaging.unstage(["*.txt"]) { try await repository.run($0) }
        let unstaged = WorkingAreaSummary(try await repository.status())

        // Assert
        #expect(staged == WorkingAreaSummary(staged: 1, unstaged: 1))
        #expect(unstaged == WorkingAreaSummary(unstaged: 1, untracked: 1))
    }

    @Test
    func unstagesBeforeTheFirstCommit() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("new\n", to: "a.txt")
        try await repository.git("add", "a.txt")

        // Act
        try await WorkingAreaStaging.unstage(["a.txt"]) { try await repository.run($0) }

        // Assert
        #expect(WorkingAreaSummary(try await repository.status()) == WorkingAreaSummary(untracked: 1))
    }

    @Test
    func manyFilesAreStagedFromAList() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        let paths = (0 ..< WorkingAreaStaging.longestPathList + 50).map { "file \($0).txt" }
        for path in paths {
            try repository.write("new\n", to: path)
        }

        // Act
        try await WorkingAreaStaging.stage(paths) { try await repository.run($0) }

        // Assert
        #expect(WorkingAreaSummary(try await repository.status()) == WorkingAreaSummary(staged: paths.count))
    }

    @Test
    func stagingTrackedChangesLeavesUntrackedFiles() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        try repository.write("changed\n", to: "a.txt")
        try repository.write("new\n", to: "b.txt")

        // Act
        try await WorkingAreaStaging.stageTracked(excluding: []) { try await repository.run($0) }

        // Assert
        #expect(WorkingAreaSummary(try await repository.status()) == WorkingAreaSummary(staged: 1, untracked: 1))
    }

    @Test
    func manyUntrackedFilesAreStagedFromTheirList() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        let paths = (0 ..< WorkingAreaStaging.longestPathList + 50).map { "new/file \($0).txt" }
        for path in paths {
            try repository.write("new\n", to: path)
        }

        // Act
        try await WorkingAreaStaging.stageUntracked(paths) { try await repository.run($0) }

        // Assert
        #expect(WorkingAreaSummary(try await repository.status()) == WorkingAreaSummary(staged: paths.count))
        #expect(try await repository.staged("new/file 0.txt") == "new\n")
    }

    @Test
    func stagingEverythingLeavesConflictsForTheUser() async throws {
        // Arrange
        let repository = try await conflictedRepository()
        defer { repository.remove() }
        try repository.write("new\n", to: "new.txt")

        // Act
        try await WorkingAreaStaging.stageAll(excluding: ["shared.txt"]) { try await repository.run($0) }

        // Assert
        #expect(WorkingAreaSummary(try await repository.status()) == WorkingAreaSummary(staged: 1, conflicted: 1))
    }

    @Test
    func unstagingEverythingKeepsAMergeInProgress() async throws {
        // Arrange
        let repository = try await conflictedRepository()
        defer { repository.remove() }
        try repository.write("resolved\n", to: "shared.txt")
        try await repository.git("add", "shared.txt")

        // Act
        try await WorkingAreaStaging.unstageAll { try await repository.run($0) }

        // Assert
        #expect(InProgressOperation.read(gitDirectory: repository.folder.appending(path: ".git")) == .merging)
    }

    @Test
    func unstagesEverythingBeforeTheFirstCommit() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("new\n", to: "a.txt")
        try await repository.git("add", "a.txt")

        // Act
        try await WorkingAreaStaging.unstageAll { try await repository.run($0) }

        // Assert
        #expect(WorkingAreaSummary(try await repository.status()) == WorkingAreaSummary(untracked: 1))
    }

    /// A merge stopped on a conflict in `shared.txt`.
    private func conflictedRepository() async throws -> FixtureRepository {
        let repository = try await FixtureRepository.make()
        try await repository.commit("Base", writing: "base\n", to: "shared.txt")
        try await repository.git("switch", "--quiet", "--create", "other")
        try await repository.commit("Theirs", writing: "theirs\n", to: "shared.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Ours", writing: "ours\n", to: "shared.txt")
        _ = try await repository.run(.changing(["merge", "other"]))
        return repository
    }

    @Test
    func discardingPutsTheStagedVersionBack() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        try repository.write("staged\n", to: "a.txt")
        try await repository.git("add", "a.txt")
        try repository.write("not staged\n", to: "a.txt")

        // Act
        try await WorkingAreaStaging.discard(["a.txt"]) { try await repository.run($0) }

        // Assert
        #expect(try repository.contents(of: "a.txt") == "staged\n")
    }

    @Test
    func commitsAndAmendsWithTheMessageAsWritten() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("a\n", to: "a.txt")
        try await repository.git("add", "a.txt")
        let message = CommitMessage(subject: "Add a", body: "Because.\n\n#42 stays, since it isn’t a comment here.")

        // Act
        try await WorkingAreaStaging.commit(message.text, amend: false) { try await repository.run($0) }
        let committed = try await repository.git("log", "-1", "--format=%B")
        try await WorkingAreaStaging.commit(CommitMessage(subject: "Add a, amended").text, amend: true) { try await repository.run($0) }
        let amended = try await repository.git("log", "--format=%s")

        // Assert
        #expect(committed == "Add a\n\nBecause.\n\n#42 stays, since it isn’t a comment here.")
        #expect(amended == "Add a, amended")
    }

    @Test
    func aFailedCommitSaysWhy() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        try repository.write("#!/bin/sh\necho 'lint failed' >&2\nexit 1\n", to: ".git/hooks/pre-commit")
        let hook = repository.folder.appending(path: ".git/hooks/pre-commit")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try repository.write("b\n", to: "a.txt")
        try await repository.git("add", "a.txt")

        // Act
        let failure = await #expect(throws: WorkingAreaStaging.Failure.self) {
            try await WorkingAreaStaging.commit("Change a", amend: false) { try await repository.run($0) }
        }

        // Assert
        #expect(String(bytes: failure?.result.standardError ?? Data(), encoding: .utf8)?.contains("lint failed") == true)
    }
}
