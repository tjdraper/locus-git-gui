import Testing

struct WorkingAreaSummaryTests {
    @Test
    func countsEachGroupAndLeavesEmptyOnesOut() {
        // Arrange
        let status = RepositoryStatus(
            branch: .init(commit: nil, name: "main", upstream: nil, ahead: nil, behind: nil),
            files: [
                .init(path: "both", originalPath: nil, state: .changed(staged: .modified, unstaged: .modified)),
                .init(path: "staged", originalPath: nil, state: .changed(staged: .added, unstaged: nil)),
                .init(path: "new", originalPath: nil, state: .untracked),
                .init(path: "ignored", originalPath: nil, state: .ignored),
            ]
        )

        // Act
        let summary = WorkingAreaSummary(status)

        // Assert
        #expect(summary == WorkingAreaSummary(staged: 2, unstaged: 1, untracked: 1))
        #expect(summary.description == "2 staged · 1 unstaged · 1 untracked")
    }

    @Test
    func aCleanWorkingTreeSaysSo() {
        // Assert
        #expect(WorkingAreaSummary().isClean)
        #expect(WorkingAreaSummary().description == "No changes")
    }
}
