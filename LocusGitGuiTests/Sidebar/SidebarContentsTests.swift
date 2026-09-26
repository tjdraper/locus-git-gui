import Foundation
import Testing

struct SidebarContentsTests {
    private func contents(refs: [String], remotes: [String] = [], stashes: [Stash] = []) -> SidebarContents {
        SidebarContents(refs: refs.map { Ref(name: $0, commit: "abc") }, remoteNames: remotes, stashes: stashes)
    }

    @Test
    func branchesAreSortedAsFinderSortsNames() {
        // Act
        let contents = contents(refs: ["refs/heads/main", "refs/heads/Zebra", "refs/heads/apple", "refs/heads/feature/login"])

        // Assert
        #expect(contents.branches.map(\.name) == ["apple", "feature/login", "main", "Zebra"])
    }

    @Test
    func tagsListTheHighestVersionFirst() {
        // Act
        let contents = contents(refs: ["refs/tags/v1.9", "refs/tags/v2.0", "refs/tags/v1.10"])

        // Assert
        #expect(contents.tags.map(\.name) == ["v2.0", "v1.10", "v1.9"])
    }

    @Test
    func remoteBranchesAreListedUnderTheirRemoteWithoutItsName() {
        // Act
        let contents = contents(
            refs: ["refs/remotes/origin/main", "refs/remotes/origin/feature/login", "refs/remotes/team/a/main"],
            remotes: ["origin", "team/a", "empty"]
        )

        // Assert
        #expect(contents.remotes.map(\.name) == ["origin", "team/a", "empty"])
        #expect(contents.remotes[0].branches.map(\.name) == ["feature/login", "main"])
        #expect(contents.remotes[1].branches.map(\.name) == ["main"])
        #expect(contents.remotes[2].branches.isEmpty)
    }

    @Test
    func aRemotesHeadIsLeftOut() {
        // Act
        let contents = SidebarContents(
            refs: [
                Ref(name: "refs/remotes/origin/HEAD", commit: "abc", symbolicTarget: "refs/remotes/origin/main"),
                Ref(name: "refs/remotes/origin/main", commit: "abc"),
            ],
            remoteNames: ["origin"],
            stashes: []
        )

        // Assert
        #expect(contents.remotes.first?.branches.map(\.name) == ["main"])
    }

    @Test
    func branchesOfARemoteNoLongerConfiguredStillShow() {
        // Act
        let contents = contents(refs: ["refs/remotes/old/main"], remotes: ["origin"])

        // Assert
        #expect(contents.remotes.map(\.name) == ["origin", "old"])
        #expect(contents.remotes.last?.branches.map(\.name) == ["main"])
    }

    @Test
    func aBranchKeepsItsTrackingWithAShortUpstreamName() throws {
        // Arrange
        let main = Ref(
            name: "refs/heads/main",
            commit: "abc",
            isCheckedOut: true,
            upstream: "refs/remotes/origin/main",
            ahead: 2,
            behind: 1
        )

        // Act
        let contents = SidebarContents(refs: [main], remoteNames: [], stashes: [])

        // Assert
        let branch = try #require(contents.branches.first)
        #expect(branch.isCheckedOut)
        #expect(branch.upstream == "origin/main")
        #expect(branch.ahead == 2)
        #expect(branch.behind == 1)
    }

    @Test
    func visibleRowsSkipCollapsedSectionsAndCollapsedRemotes() {
        // Arrange
        let contents = contents(
            refs: ["refs/heads/main", "refs/remotes/origin/main", "refs/remotes/upstream/main", "refs/tags/v1"],
            remotes: ["origin", "upstream"],
            stashes: [Stash(commit: "def", date: Date(timeIntervalSince1970: 0), message: "On main: wip")]
        )

        // Act
        let rows = contents.visibleRows(collapsedSections: [.tags], collapsedRemotes: ["origin"])

        // Assert
        #expect(rows.map(\.id) == [
            .ref("refs/heads/main"),
            .remote("origin"),
            .remote("upstream"),
            .ref("refs/remotes/upstream/main"),
            .stash("def"),
        ])
        #expect(rows.last?.name == "On main: wip")
    }

    @Test
    func containsFindsItemsInEverySection() {
        // Arrange
        let contents = contents(
            refs: ["refs/heads/main", "refs/remotes/origin/main", "refs/tags/v1"],
            remotes: ["origin"],
            stashes: [Stash(commit: "def", date: Date(timeIntervalSince1970: 0), message: "wip")]
        )

        // Act & Assert
        #expect(contents.contains(.ref("refs/heads/main")))
        #expect(contents.contains(.ref("refs/remotes/origin/main")))
        #expect(contents.contains(.ref("refs/tags/v1")))
        #expect(contents.contains(.remote("origin")))
        #expect(contents.contains(.stash("def")))
        #expect(!contents.contains(.ref("refs/heads/deleted")))
        #expect(!contents.contains(.stash("dropped")))
    }

    @Test
    func filteringKeepsNamesWithTheTextAnywhereIgnoringCaseAndAccents() {
        // Arrange
        let contents = contents(
            refs: ["refs/heads/feature/Login", "refs/heads/main", "refs/tags/login-v1", "refs/tags/v2"],
            stashes: [Stash(commit: "def", date: Date(timeIntervalSince1970: 0), message: "On main: lógin form")]
        )

        // Act
        let filtered = contents.filtered(by: "login")

        // Assert
        #expect(filtered.branches.map(\.name) == ["feature/Login"])
        #expect(filtered.tags.map(\.name) == ["login-v1"])
        #expect(filtered.stashes.map(\.id) == [.stash("def")])
    }

    @Test
    func filteringMatchesRemoteBranchesWithTheirRemotesName() {
        // Arrange
        let contents = contents(
            refs: ["refs/remotes/origin/main", "refs/remotes/origin/develop", "refs/remotes/upstream/main"],
            remotes: ["origin", "upstream"]
        )

        // Act
        let filtered = contents.filtered(by: "origin/ma")

        // Assert
        #expect(filtered.remotes.map(\.name) == ["origin"])
        #expect(filtered.remotes.first?.branches.map(\.name) == ["main"])
    }

    @Test
    func aRemoteWhoseNameMatchesKeepsAllItsBranches() {
        // Arrange
        let contents = contents(refs: ["refs/remotes/upstream/main", "refs/remotes/upstream/develop"], remotes: ["upstream"])

        // Act
        let filtered = contents.filtered(by: "upst")

        // Assert
        #expect(filtered.remotes.first?.branches.map(\.name) == ["develop", "main"])
    }

    @Test
    func anEmptyFilterKeepsEverything() {
        // Arrange
        let contents = contents(refs: ["refs/heads/main", "refs/tags/v1"])

        // Act
        let filtered = contents.filtered(by: "  ")

        // Assert
        #expect(filtered == contents)
    }

    @Test
    func aFilterMatchingNothingLeavesItEmpty() {
        // Arrange
        let contents = contents(refs: ["refs/heads/main", "refs/remotes/origin/main"], remotes: ["origin"])

        // Act
        let filtered = contents.filtered(by: "zzz")

        // Assert
        #expect(filtered.isEmpty)
    }

    @Test
    func readsARepositorysBranchesRemotesAndStashes() async throws {
        // Arrange
        let origin = try await FixtureRepository.make()
        defer { origin.remove() }
        try await origin.commit("First", writing: "a", to: "a.txt")
        let clone = try await origin.clone()
        defer { clone.remove() }
        try await clone.git("tag", "v1")
        try clone.write("changed", to: "a.txt")
        try await clone.git("stash", "--quiet")

        // Act
        let refs = try await Ref.readList { try await clone.run($0) }
        let contents = try await SidebarContents.read(refs: refs) { try await clone.run($0) }

        // Assert
        #expect(contents.branches.map(\.name) == ["main"])
        #expect(contents.remotes.map(\.name) == ["origin"])
        #expect(contents.remotes.first?.branches.map(\.name) == ["main"])
        #expect(contents.tags.map(\.name) == ["v1"])
        #expect(contents.stashes.count == 1)
    }

    @Test
    func findsTheSectionAndRemoteThatListAnItem() {
        // Arrange
        let contents = contents(
            refs: ["refs/heads/main", "refs/tags/v1", "refs/remotes/origin/main"],
            remotes: ["origin"]
        )

        // Act
        let sections = [
            SidebarItemID.ref("refs/heads/main"),
            .ref("refs/tags/v1"),
            .ref("refs/remotes/origin/main"),
            .remote("origin"),
            .ref("refs/heads/gone"),
        ].map(contents.section(containing:))

        // Assert
        #expect(sections == [.branches, .tags, .remotes, .remotes, nil])
        #expect(contents.remote(containing: .ref("refs/remotes/origin/main")) == "origin")
        #expect(contents.remote(containing: .ref("refs/heads/main")) == nil)
    }
}
