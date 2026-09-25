import Testing

struct RepositoryTitleBarTests {
    private let onMain = RepositoryStatus.Branch(commit: "0123456789abcdef", name: "main", upstream: nil, ahead: nil, behind: nil)

    private func file(_ state: RepositoryStatus.FileState) -> RepositoryStatus.File {
        RepositoryStatus.File(path: "file.txt", originalPath: nil, state: state)
    }

    private func titleBar(
        branch: RepositoryStatus.Branch? = nil,
        _ states: [RepositoryStatus.FileState],
        operation: InProgressOperation? = nil
    ) -> RepositoryTitleBar {
        RepositoryTitleBar(status: RepositoryStatus(branch: branch ?? onMain, files: states.map(file)), operation: operation)
    }

    @Test
    func aCleanRepositoryHasNoDot() {
        // Arrange
        let states: [RepositoryStatus.FileState] = [.ignored]

        // Act
        let titleBar = titleBar(states)

        // Assert
        #expect(titleBar == RepositoryTitleBar(status: .init(branch: onMain, files: []), operation: nil))
        #expect(titleBar.subtitle == "main · Clean")
        #expect(!titleBar.isEdited)
    }

    @Test(arguments: [
        ([RepositoryStatus.FileState.changed(staged: nil, unstaged: .modified)], "main · Uncommitted changes"),
        ([.untracked], "main · Uncommitted changes"),
        ([.changed(staged: .added, unstaged: nil)], "main · Staged changes"),
        ([.changed(staged: .modified, unstaged: .modified)], "main · Staged and unstaged changes"),
        ([.changed(staged: .added, unstaged: nil), .untracked], "main · Staged and unstaged changes"),
    ])
    func changesSetTheDotAndSaySoInTheSubtitle(states: [RepositoryStatus.FileState], subtitle: String) {
        // Arrange
        let changes = states

        // Act
        let titleBar = titleBar(changes)

        // Assert
        #expect(titleBar.subtitle == subtitle)
        #expect(titleBar.isEdited)
    }

    @Test
    func aDetachedHeadNamesItsCommit() {
        // Arrange
        let detached = RepositoryStatus.Branch(commit: "abcdef0123456789", name: nil, upstream: nil, ahead: nil, behind: nil)

        // Act
        let titleBar = titleBar(branch: detached, [])

        // Assert
        #expect(titleBar.subtitle == "Detached HEAD at abcdef0 · Clean")
    }

    @Test
    func aRebaseNamesTheBranchBeingRebasedAndSetsTheDot() {
        // Arrange
        let detached = RepositoryStatus.Branch(commit: "abcdef0123456789", name: nil, upstream: nil, ahead: nil, behind: nil)

        // Act
        let titleBar = titleBar(branch: detached, [], operation: .rebasing(branch: "feature", step: 2, total: 5))

        // Assert
        #expect(titleBar.subtitle == "feature · Rebasing 2 of 5")
        #expect(titleBar.isEdited)
    }

    @Test
    func aMergeInProgressOutranksTheChanges() {
        // Arrange
        let states: [RepositoryStatus.FileState] = [.conflicted(.bothModified)]

        // Act
        let titleBar = titleBar(states, operation: .merging)

        // Assert
        #expect(titleBar.subtitle == "main · Merging")
    }

    @Test
    func anUnavailableStatusSaysSoWithoutADot() {
        // Arrange
        let titleBar = RepositoryTitleBar.unavailable

        // Act
        let subtitle = titleBar.subtitle

        // Assert
        #expect(subtitle == "Status unavailable")
        #expect(!titleBar.isEdited)
    }
}
