import Foundation
import Testing

/// The branch commands run against a scratch repository, since what matters is that Git accepts
/// them and does what they say.
struct BranchCommandTests {
    @Test
    func aRemoteBranchIsCheckedOutAsALocalBranchThatTracksIt() async throws {
        // Arrange
        let origin = try await FixtureRepository.make()
        defer { origin.remove() }
        try await origin.commit("First", writing: "a", to: "a.txt")
        try await origin.git("branch", "feature")
        let clone = try await origin.clone()
        defer { clone.remove() }

        // Act
        let result = try await clone.run(BranchCommand.checkOutTracking("origin/feature", as: "mine"))

        // Assert
        #expect(result.status == 0)
        #expect(try await clone.git("branch", "--show-current") == "mine")
        #expect(try await clone.git("rev-parse", "--abbrev-ref", "mine@{upstream}") == "origin/feature")
    }

    @Test
    func aBranchIsMadeWithoutCheckingItOut() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.commit("Second", writing: "b", to: "b.txt")

        // Act
        let result = try await repository.run(BranchCommand.create("old", at: "HEAD~1", checkingOut: false))

        // Assert
        #expect(result.status == 0)
        #expect(try await repository.git("branch", "--show-current") == "main")
        #expect(try await repository.git("rev-parse", "old") == repository.git("rev-parse", "HEAD~1"))
    }

    @Test
    func deletingAnUnmergedBranchIsRefusedAndCountsItsCommits() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Second", writing: "b", to: "b.txt")
        try await repository.commit("Third", writing: "c", to: "c.txt")
        try await repository.git("tag", "kept", "HEAD~1")
        try await repository.git("switch", "--quiet", "main")

        // Act
        let refused = try await repository.run(BranchCommand.delete("feature", force: false))
        let count = try await repository.run(BranchCommand.commitsOnlyOn("feature"))
        let forced = try await repository.run(BranchCommand.delete("feature", force: true))

        // Assert
        #expect(refused.status != 0)
        #expect(RecognizedGitFailure.recognize(refused) == .branchNotMerged(branch: "feature"))
        #expect(String(bytes: count.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        #expect(forced.status == 0)
        #expect(try await repository.git("branch", "--list", "feature").isEmpty)
    }

    @Test
    func anUpstreamIsSetAndUnset() async throws {
        // Arrange
        let origin = try await FixtureRepository.make()
        defer { origin.remove() }
        try await origin.commit("First", writing: "a", to: "a.txt")
        try await origin.git("branch", "other")
        let clone = try await origin.clone()
        defer { clone.remove() }

        // Act
        let set = try await clone.run(BranchCommand.setUpstream(of: "main", to: "origin/other"))
        let upstream = try await clone.git("rev-parse", "--abbrev-ref", "main@{upstream}")
        let unset = try await clone.run(BranchCommand.unsetUpstream(of: "main"))

        // Assert
        #expect(set.status == 0)
        #expect(upstream == "origin/other")
        #expect(unset.status == 0)
        #expect(try await clone.run(.reading(["rev-parse", "main@{upstream}"])).status != 0)
    }

    @Test
    func checkingOutIsBlockedByChangesItWouldOverwrite() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Second", writing: "b", to: "a.txt")
        try await repository.git("switch", "--quiet", "main")
        try repository.write("local", to: "a.txt")

        // Act
        let result = try await repository.run(BranchCommand.checkOut("feature"))

        // Assert
        #expect(RecognizedGitFailure.recognize(result) == .localChangesWouldBeOverwritten(files: ["a.txt"], includesUntracked: false))
    }
}
