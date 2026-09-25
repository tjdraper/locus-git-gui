import Foundation
import Testing

struct GitInstallationTests {
    @Test(arguments: [
        ("git version 2.54.0 (Apple Git-157)\n", "2.54.0 (Apple Git-157)"),
        ("git version 2.42.0\n", "2.42.0"),
    ])
    func readsTheVersionGitPrints(output: String, version: String) {
        // Arrange
        let data = Data(output.utf8)

        // Act
        let parsed = GitInstallation.version(from: data)

        // Assert
        #expect(parsed == version)
    }

    @Test(arguments: ["--version\n", "git version \n", ""])
    func anythingElseIsNotAVersion(output: String) {
        // Arrange
        let data = Data(output.utf8)

        // Act
        let parsed = GitInstallation.version(from: data)

        // Assert
        #expect(parsed == nil)
    }

    @Test
    func aRealGitAnswersWithItsVersion() async throws {
        // Arrange
        let environment = ProcessInfo.processInfo.environment

        // Act
        let installation = try await GitInstallation.probe(TestGit.executableURL, environment: environment)

        // Assert
        #expect(installation.executableURL == TestGit.executableURL)
        #expect(installation.version.first?.isNumber == true)
    }

    @Test
    func anotherProgramIsNotGit() async {
        // Arrange
        let echo = URL(filePath: "/bin/echo")

        // Act & Assert
        await #expect(throws: GitInstallation.ProbeFailure.notGit) {
            try await GitInstallation.probe(echo, environment: [:])
        }
    }

    @Test
    func aFileThatCantRunIsNotExecutable() async throws {
        // Arrange
        let folder = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "git")
        try "not a program".write(to: file, atomically: true, encoding: .utf8)

        // Act & Assert
        await #expect(throws: GitInstallation.ProbeFailure.notExecutable) {
            try await GitInstallation.probe(file, environment: [:])
        }
        await #expect(throws: GitInstallation.ProbeFailure.notExecutable) {
            try await GitInstallation.probe(folder.appending(path: "missing"), environment: [:])
        }
    }
}
