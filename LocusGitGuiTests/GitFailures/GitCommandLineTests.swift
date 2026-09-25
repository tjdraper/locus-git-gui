import Testing

struct GitCommandLineTests {
    @Test
    func plainArgumentsAreLeftAsTheyAre() {
        // Arrange
        let arguments = ["status", "--porcelain=v2", "--branch", "-z"]

        // Act
        let line = GitCommandLine.display(arguments)

        // Assert
        #expect(line == "git status --porcelain=v2 --branch -z")
    }

    @Test
    func argumentsTheShellWouldSplitOrExpandAreQuoted() {
        // Arrange
        let arguments = ["commit", "--message", "Don't break it", "--format=%(refname)", ""]

        // Act
        let line = GitCommandLine.display(arguments)

        // Assert
        #expect(line == "git commit --message 'Don'\\''t break it' '--format=%(refname)' ''")
    }
}
