import Testing

struct CommitRefLabelTests {
    @Test
    func labelsAreShortenedAndOrderedByKindThenName() {
        // Arrange
        let refs = [
            Ref(name: "refs/tags/v1.10", commit: "a"),
            Ref(name: "refs/tags/v1.9", commit: "a"),
            Ref(name: "refs/remotes/origin/main", commit: "a"),
            Ref(name: "refs/heads/zebra", commit: "a"),
            Ref(name: "refs/heads/main", commit: "a", isCheckedOut: true),
            Ref(name: "refs/heads/apple", commit: "a"),
        ]

        // Act
        let labels = CommitRefLabel.byCommit(refs: refs, detachedHead: nil)["a"] ?? []

        // Assert
        #expect(labels.map(\.name) == ["main", "apple", "zebra", "origin/main", "v1.9", "v1.10"])
        #expect(labels.map(\.kind) == [.checkedOutBranch, .branch, .branch, .remoteBranch, .tag, .tag])
        #expect(labels.first?.sidebarItem == .ref("refs/heads/main"))
    }

    @Test
    func aDetachedHeadIsLabelledFirst() {
        // Arrange
        let refs = [Ref(name: "refs/tags/v1", commit: "a")]

        // Act
        let labels = CommitRefLabel.byCommit(refs: refs, detachedHead: "a")["a"] ?? []

        // Assert
        #expect(labels.map(\.name) == ["HEAD", "v1"])
        #expect(labels.first?.sidebarItem == nil)
    }

    @Test
    func aRemotesHeadIsLeftOut() {
        // Arrange
        let refs = [
            Ref(name: "refs/remotes/origin/HEAD", commit: "a", symbolicTarget: "refs/remotes/origin/main"),
            Ref(name: "refs/remotes/origin/main", commit: "a"),
        ]

        // Act
        let labels = CommitRefLabel.byCommit(refs: refs, detachedHead: nil)

        // Assert
        #expect(labels["a"]?.map(\.name) == ["origin/main"])
    }

    @Test
    func eachLabelIsOnTheCommitItPointsAt() {
        // Arrange
        let refs = [
            Ref(name: "refs/heads/main", commit: "a"),
            Ref(name: "refs/heads/feature", commit: "b"),
        ]

        // Act
        let labels = CommitRefLabel.byCommit(refs: refs, detachedHead: nil)

        // Assert
        #expect(labels["a"]?.map(\.name) == ["main"])
        #expect(labels["b"]?.map(\.name) == ["feature"])
        #expect(labels["c"] == nil)
    }
}
