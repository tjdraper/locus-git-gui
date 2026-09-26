import Testing

struct WorkingAreaFilterTests {
    @Test
    func unstagedTakesInEverythingNotYetStaged() {
        // Act
        let unstaged = WorkingAreaGroup.allCases.filter(WorkingAreaFilter.unstaged.includes)
        let staged = WorkingAreaGroup.allCases.filter(WorkingAreaFilter.staged.includes)

        // Assert
        #expect(unstaged == [.conflicted, .unstaged, .untracked])
        #expect(staged == [.staged])
        #expect(WorkingAreaGroup.allCases.allSatisfy(WorkingAreaFilter.all.includes))
    }
}
