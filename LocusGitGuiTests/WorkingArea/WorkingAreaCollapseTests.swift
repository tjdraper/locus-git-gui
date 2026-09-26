import Testing

struct WorkingAreaCollapseTests {
    private func file(_ path: String, _ group: WorkingAreaGroup) -> DiffFile {
        DiffFile(changed: ChangedFile(change: .modified, path: path, originalPath: nil), patch: FilePatch(), group: group.rawValue)
    }

    @Test
    func aCollapsedFileStaysCollapsedOnceStaged() {
        // Arrange
        let unstaged = file("a", .unstaged)
        let staged = file("a", .staged)
        let other = file("b", .unstaged)

        // Act
        let collapsed = WorkingAreaCollapse.following([unstaged.id], from: [unstaged, other], to: [staged, other])

        // Assert
        #expect(collapsed.contains(staged.id))
    }

    @Test
    func anExpandedFileStaysExpandedOnceUnstagedWhereItWasCollapsedBefore() {
        // Arrange
        let unstaged = file("a", .unstaged)
        let staged = file("a", .staged)

        // Act
        let collapsed = WorkingAreaCollapse.following([unstaged.id], from: [staged], to: [unstaged])

        // Assert
        #expect(!collapsed.contains(unstaged.id))
    }

    @Test
    func aFileAlreadyShownInTheOtherGroupKeepsItsOwnState() {
        // Arrange
        let unstaged = file("a", .unstaged)
        let staged = file("a", .staged)

        // Act
        let collapsed = WorkingAreaCollapse.following([unstaged.id], from: [staged, unstaged], to: [staged])

        // Assert
        #expect(!collapsed.contains(staged.id))
    }

    @Test
    func aStagedUntrackedFileStaysCollapsed() {
        // Arrange
        let untracked = file("new.txt", .untracked)
        let staged = file("new.txt", .staged)

        // Act
        let collapsed = WorkingAreaCollapse.following([untracked.id], from: [untracked], to: [staged])

        // Assert
        #expect(collapsed.contains(staged.id))
    }

    @Test
    func aFileThatLeavesTheWorkingAreaIsForgotten() {
        // Arrange
        let committed = file("a", .staged)

        // Act
        let collapsed = WorkingAreaCollapse.following([committed.id], from: [committed], to: [file("b", .unstaged)])

        // Assert
        #expect(collapsed.isEmpty)
    }
}
