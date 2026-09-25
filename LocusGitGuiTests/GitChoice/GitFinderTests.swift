import Foundation
import Testing

struct GitFinderTests {
    private func candidates(
        searchPath: String?,
        includesShim: Bool = true,
        executables: Set<String>,
        links: [String: String] = [:]
    ) -> [String] {
        GitFinder.candidates(
            searchPath: searchPath,
            includesShim: includesShim,
            isExecutable: { executables.contains($0) },
            resolve: { URL(filePath: links[$0.path] ?? $0.path) }
        )
        .map(\.path)
    }

    @Test
    func theSearchPathComesFirstThenHomebrewThenTheSystemGit() {
        // Arrange
        let executables: Set = ["/custom/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]

        // Act
        let found = candidates(searchPath: "/custom/bin:/usr/bin", executables: executables)

        // Assert
        #expect(found == ["/custom/bin/git", "/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"])
    }

    @Test
    func linksToTheSameGitCountOnceUnderThePathFoundFirst() {
        // Arrange
        let executables: Set = ["/usr/local/bin/git", "/opt/homebrew/bin/git"]
        let links = [
            "/usr/local/bin/git": "/opt/homebrew/Cellar/git/2.54.0/bin/git",
            "/opt/homebrew/bin/git": "/opt/homebrew/Cellar/git/2.54.0/bin/git",
        ]

        // Act
        let found = candidates(searchPath: "/usr/local/bin", executables: executables, links: links)

        // Assert
        #expect(found == ["/usr/local/bin/git"])
    }

    @Test
    func theShimIsLeftOutWithoutTheCommandLineTools() {
        // Arrange
        let executables: Set = ["/usr/bin/git"]

        // Act
        let found = candidates(searchPath: "/usr/bin:/bin", includesShim: false, executables: executables)

        // Assert
        #expect(found.isEmpty)
    }

    @Test
    func relativeSearchPathEntriesAreIgnored() {
        // Arrange
        let executables: Set = ["./git", "bin/git", "/opt/homebrew/bin/git"]

        // Act
        let found = candidates(searchPath: ".:bin:", executables: executables)

        // Assert
        #expect(found == ["/opt/homebrew/bin/git"])
    }

    @Test
    func findsAtLeastOneGitOnThisMac() async {
        // Arrange
        let environment = ProcessInfo.processInfo.environment

        // Act
        let result = await GitFinder.find(environment: environment)

        // Assert
        #expect(!result.installations.isEmpty)
        #expect(Set(result.installations.map { ResolvedPath.of($0.executableURL) }).count == result.installations.count)
    }
}
