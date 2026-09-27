import Foundation
import Testing

/// The remote commands run against a bare repository in a scratch folder, since what matters is
/// that Git accepts them and does what they say.
struct RemoteCommandTests {
    @Test
    func aFirstPushSetsTheUpstream() async throws {
        // Arrange
        let bare = try FixtureRepository(folder: TestGit.makeScratchFolder())
        defer { bare.remove() }
        try await bare.git("init", "--quiet", "--bare", "--initial-branch=main")
        let clone = try await bare.clone()
        defer { clone.remove() }
        try await clone.git("checkout", "--quiet", "-b", "feature")
        try await clone.commit("First", writing: "a", to: "a.txt")

        // Act
        let result = try await clone.run(RemoteCommand.pushSettingUpstream(branch: "feature", to: "origin"))

        // Assert
        #expect(result.status == 0)
        #expect(try await clone.git("rev-parse", "--abbrev-ref", "feature@{upstream}") == "origin/feature")
    }

    @Test
    func anAutomaticFetchOnlyMovesRemoteTrackingBranches() async throws {
        // Arrange
        let bare = try FixtureRepository(folder: TestGit.makeScratchFolder())
        defer { bare.remove() }
        try await bare.git("init", "--quiet", "--bare", "--initial-branch=main")
        let first = try await bare.clone()
        let second = try await bare.clone()
        defer { [first, second].forEach { $0.remove() } }
        try await first.git("checkout", "--quiet", "-b", "main")
        try await first.commit("First", writing: "a", to: "a.txt")
        try await first.git("push", "--quiet", "--set-upstream", "origin", "main")
        try await second.git("fetch", "--quiet")
        try await second.git("checkout", "--quiet", "main")
        try await first.commit("Second", writing: "b", to: "b.txt")
        try await first.git("tag", "v1")
        try await first.git("push", "--quiet", "origin", "main", "v1")
        let before = try await second.git("rev-parse", "main")
        // Left by the fetch above.
        try FileManager.default.removeItem(at: second.folder.appending(path: ".git/FETCH_HEAD"))

        // Act
        let result = try await second.run(RemoteCommand.automaticFetch(prunes: true))

        // Assert
        #expect(result.status == 0)
        #expect(try await second.git("rev-parse", "main") == before)
        #expect(try await second.git("rev-parse", "origin/main") == first.git("rev-parse", "main"))
        #expect(try await second.git("tag", "--list").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: second.folder.appending(path: ".git/FETCH_HEAD").path))
    }

    @Test
    func aTagIsPushedAndDeletedOnTheRemote() async throws {
        // Arrange
        let bare = try FixtureRepository(folder: TestGit.makeScratchFolder())
        defer { bare.remove() }
        try await bare.git("init", "--quiet", "--bare", "--initial-branch=main")
        let clone = try await bare.clone()
        defer { clone.remove() }
        try await clone.git("checkout", "--quiet", "-b", "main")
        try await clone.commit("First", writing: "a", to: "a.txt")
        try await clone.git("tag", "v1")

        // Act
        let pushed = try await clone.run(RemoteCommand.pushTag("v1", to: "origin"))
        let tagsAfterPush = try await bare.git("tag", "--list")
        let deleted = try await clone.run(RemoteCommand.deleteTag("v1", from: "origin"))

        // Assert
        #expect(pushed.status == 0)
        #expect(tagsAfterPush == "v1")
        #expect(deleted.status == 0)
        #expect(try await bare.git("tag", "--list").isEmpty)
        #expect(try await clone.git("tag", "--list") == "v1")
    }

    @Test
    func pruningRemovesARemoteBranchDeletedOnTheRemote() async throws {
        // Arrange
        let bare = try FixtureRepository(folder: TestGit.makeScratchFolder())
        defer { bare.remove() }
        try await bare.git("init", "--quiet", "--bare", "--initial-branch=main")
        let clone = try await bare.clone()
        defer { clone.remove() }
        try await clone.git("checkout", "--quiet", "-b", "main")
        try await clone.commit("First", writing: "a", to: "a.txt")
        try await clone.git("push", "--quiet", "origin", "main", "main:feature")
        try await bare.git("branch", "--quiet", "-D", "feature")

        // Act
        let plain = try await clone.run(RemoteCommand.fetchAll())
        let afterPlain = try await clone.git("branch", "--remotes")
        let pruned = try await clone.run(RemoteCommand.fetchAll(.prune))

        // Assert
        #expect(plain.status == 0)
        #expect(afterPlain.contains("origin/feature"))
        #expect(pruned.status == 0)
        #expect(try await clone.git("branch", "--remotes") == "origin/main")
    }

    @Test
    func fetchingTagsBringsATagOnNoBranch() async throws {
        // Arrange
        let bare = try FixtureRepository(folder: TestGit.makeScratchFolder())
        defer { bare.remove() }
        try await bare.git("init", "--quiet", "--bare", "--initial-branch=main")
        let first = try await bare.clone()
        let second = try await bare.clone()
        defer { [first, second].forEach { $0.remove() } }
        try await first.git("checkout", "--quiet", "-b", "main")
        try await first.commit("First", writing: "a", to: "a.txt")
        try await first.git("push", "--quiet", "origin", "main")
        try await first.commit("Only tagged", writing: "b", to: "b.txt")
        try await first.git("tag", "experiment")
        try await first.git("push", "--quiet", "origin", "experiment")

        // Act
        _ = try await second.run(RemoteCommand.fetchAll())
        let tagsAfterPlain = try await second.git("tag", "--list")
        let withTags = try await second.run(RemoteCommand.fetchAll(.tags))

        // Assert
        #expect(tagsAfterPlain.isEmpty)
        #expect(withTags.status == 0)
        #expect(try await second.git("tag", "--list") == "experiment")
    }
}
