import Testing

struct HistoryScopeTests {
    private let refs = [
        Ref(name: "refs/heads/main", commit: "m1", isCheckedOut: true),
        Ref(name: "refs/heads/feature", commit: "f1"),
        Ref(name: "refs/tags/v1", commit: "t1"),
        Ref(name: "refs/remotes/origin/HEAD", commit: "o1", symbolicTarget: "refs/remotes/origin/main"),
        Ref(name: "refs/remotes/origin/main", commit: "o1"),
        Ref(name: "refs/remotes/origin/release", commit: "o1"),
        Ref(name: "refs/remotes/origin/topic", commit: "o2"),
        Ref(name: "refs/remotes/upstream/main", commit: "u1"),
    ]

    private func resolve(_ selection: SidebarItemID?, head: String? = "m1") -> HistoryScope {
        let contents = SidebarContents(refs: refs, remoteNames: ["origin", "upstream", "empty"], stashes: [])
        return HistoryScope.resolve(selection: selection, refs: refs, contents: contents, head: head)
    }

    @Test
    func nothingSelectedShowsTheCheckedOutCommit() {
        // Act
        let scope = resolve(nil, head: "detached")

        // Assert
        #expect(scope.tips == ["detached"])
    }

    @Test
    func aRepositoryWithNoCommitsHasAnEmptyHistory() {
        // Act
        let scope = resolve(nil, head: nil)

        // Assert
        #expect(scope.tips.isEmpty)
    }

    @Test
    func aBranchOrTagShowsTheCommitItPointsAt() {
        // Act
        let branch = resolve(.ref("refs/heads/feature"))
        let tag = resolve(.ref("refs/tags/v1"))

        // Assert
        #expect(branch.tips == ["f1"])
        #expect(tag.tips == ["t1"])
    }

    @Test
    func aRemoteShowsAllItsBranchesOnce() {
        // Act
        let scope = resolve(.remote("origin"))

        // Assert
        #expect(scope.tips == ["o1", "o2"])
    }

    @Test
    func aRemoteWithNothingFetchedHasAnEmptyHistory() {
        // Act
        let scope = resolve(.remote("empty"))

        // Assert
        #expect(scope.tips.isEmpty)
    }

    @Test
    func aStashShowsItsOwnCommit() {
        // Act
        let scope = resolve(.stash("s1"))

        // Assert
        #expect(scope.tips == ["s1"])
    }

    @Test
    func aSelectionThatIsGoneFallsBackToTheCheckedOutCommit() {
        // Act
        let scope = resolve(.ref("refs/heads/deleted"))

        // Assert
        #expect(scope.tips == ["m1"])
    }
}
