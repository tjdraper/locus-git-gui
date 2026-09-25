import Foundation
import Testing

struct TypedGitPathTests {
    @Test(arguments: [
        ("/opt/homebrew/bin/git", "/opt/homebrew/bin/git"),
        ("  /opt/homebrew/bin/git\n", "/opt/homebrew/bin/git"),
        ("'/Applications/My Tools/git'", "/Applications/My Tools/git"),
        ("\"/Applications/My Tools/git\"", "/Applications/My Tools/git"),
        ("/Applications/My\\ Tools/git", "/Applications/My Tools/git"),
    ])
    func acceptsFullPathsAsTerminalCopiesThem(text: String, path: String) {
        // Arrange
        let typed = text

        // Act
        let url = TypedGitPath.url(from: typed)

        // Assert
        #expect(url?.path == path)
    }

    @Test
    func expandsTheHomeFolder() {
        // Arrange
        let typed = "~/bin/git"

        // Act
        let url = TypedGitPath.url(from: typed)

        // Assert
        #expect(url?.path == NSHomeDirectory() + "/bin/git")
    }

    @Test(arguments: ["", "   ", "git", "bin/git", "./git"])
    func rejectsAnythingButAFullPath(text: String) {
        // Arrange
        let typed = text

        // Act
        let url = TypedGitPath.url(from: typed)

        // Assert
        #expect(url == nil)
    }
}
