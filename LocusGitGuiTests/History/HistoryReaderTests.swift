import Foundation
import Testing

struct HistoryReaderTests {
    private func read(
        _ repository: FixtureRepository,
        tips: [String],
        search: HistorySearch? = nil,
        skip: Int = 0,
        count: Int = 100
    ) async throws -> [String] {
        try await HistoryReader.read(HistoryScope(tips: tips), search: search, skip: skip, count: count) { command in
            try await repository.run(command)
        }.map(\.subject)
    }

    private func makeRepository(commits subjects: [String]) async throws -> FixtureRepository {
        let repository = try await FixtureRepository.make()
        for (index, subject) in subjects.enumerated() {
            try await repository.commit(subject, writing: "\(index)", to: "file.txt")
        }
        return repository
    }

    @Test
    func pagesCarryOnWhereTheLastOneStopped() async throws {
        // Arrange
        let repository = try await makeRepository(commits: ["One", "Two", "Three", "Four", "Five"])
        defer { repository.remove() }
        let head = try await repository.git("rev-parse", "HEAD")

        // Act
        let first = try await read(repository, tips: [head], count: 2)
        let second = try await read(repository, tips: [head], skip: 2, count: 2)
        let last = try await read(repository, tips: [head], skip: 4, count: 2)

        // Assert
        #expect(first == ["Five", "Four"])
        #expect(second == ["Three", "Two"])
        #expect(last == ["One"])
    }

    @Test
    func aHistoryWithNothingToStartFromIsEmpty() async throws {
        // Arrange
        let repository = try await makeRepository(commits: ["One"])
        defer { repository.remove() }

        // Act
        let subjects = try await read(repository, tips: [])

        // Assert
        #expect(subjects.isEmpty)
    }

    @Test
    func severalTipsShowEveryCommitReachableFromThem() async throws {
        // Arrange
        let repository = try await makeRepository(commits: ["Base"])
        defer { repository.remove() }
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("On feature", writing: "f", to: "f.txt")
        let feature = try await repository.git("rev-parse", "HEAD")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("On main", writing: "m", to: "m.txt")
        let main = try await repository.git("rev-parse", "HEAD")

        // Act
        let subjects = try await read(repository, tips: [main, feature])

        // Assert
        #expect(Set(subjects) == ["On main", "On feature", "Base"])
        #expect(subjects.last == "Base")
    }

    @Test
    func aMessageSearchIgnoresCaseAndTakesTheTextAsTyped() async throws {
        // Arrange
        let repository = try await makeRepository(commits: ["Fix the (parser)", "Add docs", "fix THE (PARSER) again", "Fix the parser"])
        defer { repository.remove() }
        let head = try await repository.git("rev-parse", "HEAD")

        // Act
        let subjects = try await read(repository, tips: [head], search: HistorySearch(text: "fix the (parser)", field: .message))

        // Assert
        #expect(subjects == ["fix THE (PARSER) again", "Fix the (parser)"])
    }

    @Test
    func pagesOfASearchSkipOnlyMatches() async throws {
        // Arrange
        let repository = try await makeRepository(commits: ["Match 1", "Other", "Match 2", "Other", "Match 3"])
        defer { repository.remove() }
        let head = try await repository.git("rev-parse", "HEAD")
        let search = HistorySearch(text: "match", field: .message)

        // Act
        let second = try await read(repository, tips: [head], search: search, skip: 1, count: 1)

        // Assert
        #expect(second == ["Match 2"])
    }

    @Test
    func anAuthorSearchMatchesNameOrEmail() async throws {
        // Arrange
        let repository = try await makeRepository(commits: ["By the test author"])
        defer { repository.remove() }
        try repository.write("ada", to: "ada.txt")
        try await repository.git("add", "ada.txt")
        try await repository.git(
            "commit", "--quiet", "--message", "By Ada",
            environment: ["GIT_AUTHOR_NAME": "Ada Lovelace", "GIT_AUTHOR_EMAIL": "countess@example.com"]
        )
        let head = try await repository.git("rev-parse", "HEAD")

        // Act
        let byName = try await read(repository, tips: [head], search: HistorySearch(text: "lovelace", field: .author))
        let byEmail = try await read(repository, tips: [head], search: HistorySearch(text: "countess@", field: .author))

        // Assert
        #expect(byName == ["By Ada"])
        #expect(byEmail == ["By Ada"])
    }

    @Test
    func aChangesSearchFindsCommitsThatAddOrRemoveTheText() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Add needle", writing: "hay needle hay", to: "a.txt")
        try await repository.commit("Unrelated", writing: "other", to: "b.txt")
        try await repository.commit("Remove needle", writing: "hay hay", to: "a.txt")
        let head = try await repository.git("rev-parse", "HEAD")

        // Act
        let subjects = try await read(repository, tips: [head], search: HistorySearch(text: "needle", field: .changes))

        // Assert
        #expect(subjects == ["Remove needle", "Add needle"])
    }

    @Test
    func aTypedHashFindsItsCommit() async throws {
        // Arrange
        let repository = try await makeRepository(commits: ["One", "Two"])
        defer { repository.remove() }
        let first = try await repository.git("rev-parse", "HEAD~1")

        // Act
        let match = try await HistoryReader.readHashMatch(String(first.prefix(8))) { try await repository.run($0) }

        // Assert
        #expect(match?.hash == first)
        #expect(match?.subject == "One")
    }

    @Test
    func aHashThatNamesNothingIsNoMatch() async throws {
        // Arrange
        let repository = try await makeRepository(commits: ["One"])
        defer { repository.remove() }

        // Act
        let match = try await HistoryReader.readHashMatch("deadbeef") { try await repository.run($0) }

        // Assert
        #expect(match == nil)
    }

    @Test
    func aStreamedPageHandsOverItsCommitsAndCountsThem() async throws {
        // Arrange
        let repository = try await makeRepository(commits: ["One", "Two", "Three", "Four", "Five"])
        defer { repository.remove() }
        let head = try await repository.git("rev-parse", "HEAD")
        var received: [String] = []

        // Act
        let count = try await HistoryReader.stream(HistoryScope(tips: [head]), search: nil, commits: 1 ..< 4) { command, onOutput in
            let result = try await repository.run(command)
            onOutput(result.standardOutput)
            return result
        } receive: { commits in
            received += commits.map(\.subject)
        }

        // Assert
        #expect(count == 3)
        #expect(received == ["Four", "Three", "Two"])
    }
}
