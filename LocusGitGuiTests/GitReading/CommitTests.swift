import Foundation
import Testing

struct CommitTests {
    private func log(of repository: FixtureRepository, _ arguments: String...) async throws -> [Commit] {
        let result = try await repository.run(Commit.logCommand(arguments))
        #expect(result.status == 0)
        return try Commit.parseLog(result.standardOutput)
    }

    @Test
    func commitsComeNewestFirstWithTheirParents() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Root", writing: "a", to: "a.txt")
        let root = try await repository.git("rev-parse", "HEAD")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("On feature", writing: "f", to: "f.txt")
        let feature = try await repository.git("rev-parse", "HEAD")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("On main", writing: "m", to: "m.txt")
        let main = try await repository.git("rev-parse", "HEAD")
        try await repository.git("merge", "--quiet", "--no-ff", "--no-edit", "feature")
        let merge = try await repository.git("rev-parse", "HEAD")

        // Act
        let commits = try await log(of: repository, "--topo-order")

        // Assert
        #expect(commits.first?.hash == merge)
        #expect(commits.first?.parents == [main, feature])
        #expect(commits.last?.hash == root)
        #expect(commits.last?.parents == [])
        #expect(commits.count == 4)
    }

    @Test
    func authorAndCommitterAreKeptApart() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("a", to: "a.txt")
        try await repository.git("add", "a.txt")
        try await repository.git(
            "commit", "--quiet", "--message", "Applied patch",
            environment: [
                "GIT_AUTHOR_NAME": "Ada Lovelace",
                "GIT_AUTHOR_EMAIL": "ada@example.com",
                "GIT_AUTHOR_DATE": "@1700000000 +0000",
                "GIT_COMMITTER_NAME": "Grace Hopper",
                "GIT_COMMITTER_EMAIL": "grace@example.com",
                "GIT_COMMITTER_DATE": "@1800000000 +0000",
            ]
        )

        // Act
        let commits = try await log(of: repository)

        // Assert
        let commit = try #require(commits.first)
        #expect(commit.author.name == "Ada Lovelace")
        #expect(commit.author.email == "ada@example.com")
        #expect(commit.author.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(commit.committer.name == "Grace Hopper")
        #expect(commit.committer.email == "grace@example.com")
        #expect(commit.committer.date == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test
    func theSubjectIsTheFirstParagraphOnly() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("a", to: "a.txt")
        try await repository.git("add", "a.txt")
        try await repository.git("commit", "--quiet", "--message", "Füge Übersetzung hinzu\n\nThe body goes here.")

        // Act
        let commits = try await log(of: repository)

        // Assert
        #expect(commits.map(\.subject) == ["Füge Übersetzung hinzu"])
    }

    @Test
    func anEmptySubjectDoesNotShiftTheFieldsAfterIt() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try repository.write("b", to: "b.txt")
        try await repository.git("add", "b.txt")
        try await repository.git("commit", "--quiet", "--allow-empty-message", "--message", "")

        // Act
        let commits = try await log(of: repository)

        // Assert
        #expect(commits.map(\.subject) == ["", "First"])
    }

    @Test
    func anEmptyRangeHasNoCommits() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")

        // Act
        let commits = try await log(of: repository, "HEAD..HEAD")

        // Assert
        #expect(commits.isEmpty)
    }

    @Test
    func aTruncatedLogIsUnreadable() {
        // Arrange
        let output = Data("abc\0\0Ada\0".utf8)

        // Act & Assert
        #expect(throws: UnreadableGitOutput.self) {
            try Commit.parseLog(output)
        }
    }
}
