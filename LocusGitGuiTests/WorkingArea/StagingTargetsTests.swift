import Testing

struct StagingTargetsTests {
    private func file(_ path: String, _ group: WorkingAreaGroup) -> DiffFile {
        DiffFile(changed: ChangedFile(change: .modified, path: path, originalPath: nil), patch: FilePatch(), group: group.rawValue)
    }

    @Test
    func stagingAMixedPickStagesWhatIsntStaged() {
        // Arrange
        let targets = StagingTargets(files: [file("a", .staged), file("b", .unstaged), file("c", .untracked), file("d", .conflicted)])

        // Act
        let toggle = targets.toggle

        // Assert
        #expect(toggle == .stage([file("b", .unstaged), file("c", .untracked)]))
        #expect(targets.toggleTitle == "Stage 2 Files")
    }

    @Test
    func whenEverythingPickedIsStagedItsUnstaged() {
        // Arrange
        let targets = StagingTargets(files: [file("a", .staged), file("b", .staged)])

        // Assert
        #expect(targets.toggle == .unstage(targets.files))
        #expect(targets.toggleTitle == "Unstage 2 Files")
        #expect(targets.toDiscard.isEmpty)
    }

    @Test
    func conflictsAreOnlyResolvedWhenTheyreAllThatsPicked() {
        // Arrange
        let targets = StagingTargets(files: [file("a", .conflicted), file("b", .staged)])

        // Assert
        #expect(targets.toggle == .resolve([file("a", .conflicted)]))
    }

    @Test
    func discardingOnlyUntrackedFilesMovesThemToTheTrash() {
        // Arrange
        let untracked = StagingTargets(files: [file("a", .untracked), file("b", .untracked)])
        let mixed = StagingTargets(files: [file("a", .untracked), file("b", .unstaged), file("c", .staged)])

        // Assert
        #expect(untracked.discardTitle == "Move 2 Files to Trash…")
        #expect(mixed.discardTitle == "Discard 2 Files…")
        #expect(mixed.discardButtonTitle == "Discard 2 Files…")
    }

    @Test
    func oneFilesButtonsAreShort() {
        // Arrange
        let targets = StagingTargets(files: [file("a", .untracked)])

        // Assert
        #expect(targets.stageButtonTitle == "Stage")
        #expect(targets.discardButtonTitle == "Move to Trash…")
    }
}
