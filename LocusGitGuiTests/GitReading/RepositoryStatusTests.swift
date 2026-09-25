import Foundation
import Testing

struct RepositoryStatusTests {
    private func status(of repository: FixtureRepository) async throws -> RepositoryStatus {
        let result = try await repository.run(RepositoryStatus.command)
        #expect(result.status == 0)
        return try RepositoryStatus(parsing: result.standardOutput)
    }

    private func byPath(_ files: [RepositoryStatus.File]) -> [RepositoryStatus.File] {
        files.sorted { $0.path < $1.path }
    }

    @Test
    func aRepositoryWithNoCommitsHasABranchButNoCommit() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }

        // Act
        let status = try await status(of: repository)

        // Assert
        #expect(status.branch == .init(commit: nil, name: "main", upstream: nil, ahead: nil, behind: nil))
        #expect(status.files.isEmpty)
    }

    @Test
    func aCleanRepositoryHasItsCommitAndNoFiles() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        let head = try await repository.git("rev-parse", "HEAD")

        // Act
        let status = try await status(of: repository)

        // Assert
        #expect(status.branch == .init(commit: head, name: "main", upstream: nil, ahead: nil, behind: nil))
        #expect(status.files.isEmpty)
    }

    @Test
    func stagedUnstagedAndUntrackedChangesAreToldApart() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "unstaged.txt")
        try await repository.commit("Second", writing: "b", to: "both.txt")
        try await repository.commit("Third", writing: "d", to: "deleted.txt")
        try repository.write("a changed", to: "unstaged.txt")
        try repository.write("b staged", to: "both.txt")
        try await repository.git("add", "both.txt")
        try repository.write("b staged then changed", to: "both.txt")
        try repository.write("new", to: "added.txt")
        try await repository.git("add", "added.txt")
        try await repository.git("rm", "--quiet", "deleted.txt")
        try repository.write("untracked", to: "résumé draft.txt")

        // Act
        let status = try await status(of: repository)

        // Assert
        #expect(byPath(status.files) == [
            .init(path: "added.txt", originalPath: nil, state: .changed(staged: .added, unstaged: nil)),
            .init(path: "both.txt", originalPath: nil, state: .changed(staged: .modified, unstaged: .modified)),
            .init(path: "deleted.txt", originalPath: nil, state: .changed(staged: .deleted, unstaged: nil)),
            .init(path: "résumé draft.txt", originalPath: nil, state: .untracked),
            .init(path: "unstaged.txt", originalPath: nil, state: .changed(staged: nil, unstaged: .modified)),
        ])
    }

    @Test
    func aRenameKeepsWhereTheFileCameFrom() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "contents", to: "old name.txt")
        try await repository.git("mv", "old name.txt", "new name.txt")

        // Act
        let status = try await status(of: repository)

        // Assert
        #expect(status.files == [
            .init(path: "new name.txt", originalPath: "old name.txt", state: .changed(staged: .renamed, unstaged: nil)),
        ])
    }

    @Test
    func aPathStartingWithACombiningMarkIsReadWhole() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        let name = "\u{301}accent.txt"
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("untracked", to: name)

        // Act
        let status = try await status(of: repository)

        // Assert
        #expect(status.files.map(\.path) == [name])
    }

    @Test
    func aMergeConflictIsReported() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Base", writing: "base", to: "shared.txt")
        try await repository.git("switch", "--quiet", "--create", "other")
        try await repository.commit("Theirs", writing: "theirs", to: "shared.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Ours", writing: "ours", to: "shared.txt")
        _ = try await repository.run(.changing(["merge", "other"]))

        // Act
        let status = try await status(of: repository)

        // Assert
        #expect(status.files == [.init(path: "shared.txt", originalPath: nil, state: .conflicted(.bothModified))])
    }

    @Test
    func aDetachedHeadHasACommitButNoBranchName() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("switch", "--quiet", "--detach")
        let head = try await repository.git("rev-parse", "HEAD")

        // Act
        let status = try await status(of: repository)

        // Assert
        #expect(status.branch == .init(commit: head, name: nil, upstream: nil, ahead: nil, behind: nil))
    }

    @Test
    func anUpstreamComesWithAheadAndBehindCounts() async throws {
        // Arrange
        let origin = try await FixtureRepository.make()
        defer { origin.remove() }
        try await origin.commit("First", writing: "a", to: "a.txt")
        let clone = try await origin.clone()
        defer { clone.remove() }
        try await origin.commit("On the remote", writing: "remote", to: "remote.txt")
        try await clone.commit("Local one", writing: "one", to: "one.txt")
        try await clone.commit("Local two", writing: "two", to: "two.txt")
        try await clone.git("fetch", "--quiet")

        // Act
        let status = try await status(of: clone)

        // Assert
        #expect(status.branch.name == "main")
        #expect(status.branch.upstream == "origin/main")
        #expect(status.branch.ahead == 2)
        #expect(status.branch.behind == 1)
    }

    @Test
    func anUnknownRecordIsUnreadable() {
        // Arrange
        let output = Data("# branch.head main\0x something new\0".utf8)

        // Act & Assert
        #expect(throws: UnreadableGitOutput.self) {
            try RepositoryStatus(parsing: output)
        }
    }
}
