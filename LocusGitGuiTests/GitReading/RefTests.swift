import Foundation
import Testing

struct RefTests {
    private func refs(of repository: FixtureRepository) async throws -> [String: Ref] {
        let result = try await repository.run(Ref.listCommand)
        #expect(result.status == 0)
        return try Dictionary(uniqueKeysWithValues: Ref.parseList(result.standardOutput).map { ($0.name, $0) })
    }

    @Test
    func branchesAndTagsPointAtTheirCommits() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        let first = try await repository.git("rev-parse", "HEAD")
        try await repository.git("tag", "lightweight")
        try await repository.git("branch", "feature")
        try await repository.commit("Second", writing: "b", to: "b.txt")
        let second = try await repository.git("rev-parse", "HEAD")
        try await repository.git("tag", "--annotate", "annotated", "--message", "Release")

        // Act
        let refs = try await refs(of: repository)

        // Assert
        #expect(refs == [
            "refs/heads/main": Ref(name: "refs/heads/main", commit: second, isCheckedOut: true),
            "refs/heads/feature": Ref(name: "refs/heads/feature", commit: first),
            "refs/tags/lightweight": Ref(name: "refs/tags/lightweight", commit: first),
            "refs/tags/annotated": Ref(name: "refs/tags/annotated", commit: second),
        ])
        #expect(refs["refs/heads/main"]?.kind == .localBranch)
        #expect(refs["refs/tags/annotated"]?.kind == .tag)
    }

    @Test
    func remoteBranchesAndUpstreamCounts() async throws {
        // Arrange
        let origin = try await FixtureRepository.make()
        defer { origin.remove() }
        try await origin.commit("First", writing: "a", to: "a.txt")
        let clone = try await origin.clone()
        defer { clone.remove() }
        try await clone.git("branch", "level", "--track", "origin/main")
        try await origin.commit("On the remote", writing: "remote", to: "remote.txt")
        try await clone.commit("Local one", writing: "one", to: "one.txt")
        try await clone.commit("Local two", writing: "two", to: "two.txt")
        try await clone.git("branch", "untracked")
        try await clone.git("fetch", "--quiet")
        try await clone.git("switch", "--quiet", "level")
        try await clone.git("merge", "--quiet", "--ff-only", "origin/main")

        // Act
        let refs = try await refs(of: clone)

        // Assert
        let main = try #require(refs["refs/heads/main"])
        #expect(main.upstream == "refs/remotes/origin/main")
        #expect(main.ahead == 2)
        #expect(main.behind == 1)
        let level = try #require(refs["refs/heads/level"])
        #expect(level.ahead == 0)
        #expect(level.behind == 0)
        let untracked = try #require(refs["refs/heads/untracked"])
        #expect(untracked.upstream == nil)
        #expect(untracked.ahead == nil)
        #expect(refs["refs/remotes/origin/main"]?.kind == .remoteBranch)
        #expect(refs["refs/remotes/origin/HEAD"]?.symbolicTarget == "refs/remotes/origin/main")
    }

    @Test
    func anUpstreamDeletedOnTheRemoteIsGone() async throws {
        // Arrange
        let origin = try await FixtureRepository.make()
        defer { origin.remove() }
        try await origin.commit("First", writing: "a", to: "a.txt")
        let clone = try await origin.clone()
        defer { clone.remove() }
        try await clone.git("switch", "--quiet", "--create", "topic")
        try await clone.git("push", "--quiet", "--set-upstream", "origin", "topic")
        try await origin.git("branch", "--delete", "topic")
        try await clone.git("fetch", "--quiet", "--prune")

        // Act
        let refs = try await refs(of: clone)

        // Assert
        let topic = try #require(refs["refs/heads/topic"])
        #expect(topic.upstream == "refs/remotes/origin/topic")
        #expect(topic.isUpstreamGone)
        #expect(topic.ahead == nil)
    }

    @Test
    func aRefWithMissingFieldsIsUnreadable() {
        // Arrange
        let output = Data("refs/heads/main\0abc\n".utf8)

        // Act & Assert
        #expect(throws: UnreadableGitOutput.self) {
            try Ref.parseList(output)
        }
    }
}
