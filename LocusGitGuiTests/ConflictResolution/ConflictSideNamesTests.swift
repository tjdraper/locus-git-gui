import Testing

struct ConflictSideNamesTests {
    @Test
    func aMergeNamesTheCheckedOutBranchAndWhatsMergedIn() {
        // Act
        let names = ConflictSideNames(
            operation: .merging,
            checkedOutBranch: "main",
            rebaseOnto: "origin/main",
            theirsLabel: "feature",
            theirsCommit: nil
        )

        // Assert
        #expect(names == ConflictSideNames(ours: "main", theirs: "feature"))
    }

    @Test
    func aRebaseNamesTheBranchItsGoingOnto() {
        // Act
        let names = ConflictSideNames(
            operation: .rebasing(branch: "feature", step: 1, total: 2),
            checkedOutBranch: nil,
            rebaseOnto: "main",
            theirsLabel: "305d367 (Fix the parser)",
            theirsCommit: nil
        )

        // Assert
        #expect(names == ConflictSideNames(ours: "main", theirs: "305d367 (Fix the parser)"))
    }

    @Test
    func withoutALabelTheCommitNamesTheirSide() {
        // Act
        let names = ConflictSideNames(
            operation: .cherryPicking,
            checkedOutBranch: nil,
            rebaseOnto: nil,
            theirsLabel: " ",
            theirsCommit: "feature"
        )

        // Assert
        #expect(names == ConflictSideNames(ours: "HEAD", theirs: "feature"))
    }

    @Test
    func aCommitIsNamedByTheBranchAtIt() {
        // Arrange
        let refs = [
            Ref(name: "refs/remotes/origin/feature", commit: "abc"),
            Ref(name: "refs/heads/feature", commit: "abc"),
        ]

        // Assert
        #expect(ConflictSideNames.name(of: "abc", in: refs) == "feature")
        #expect(ConflictSideNames.name(of: "305d367aaaaaaaaa", in: refs) == "305d367")
    }
}
