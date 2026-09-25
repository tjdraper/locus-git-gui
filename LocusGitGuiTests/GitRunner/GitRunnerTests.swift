import Foundation
import Testing

struct GitRunnerTests {
    @Test
    func messagesComeBackInEnglishWhateverTheShellAsksFor() async throws {
        // Arrange
        let folder = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "de_DE.UTF-8"
        environment["LANG"] = "de_DE.UTF-8"
        environment["LANGUAGE"] = "de"

        // Act
        let result = try await TestGit.runner(environment: environment).run(.reading(["status"]), in: folder)

        // Assert
        #expect(result.status == 128)
        #expect(String(bytes: result.standardError, encoding: .utf8)?.contains("not a git repository") == true)
    }

    @Test
    func runsInTheGivenFolder() async throws {
        // Arrange
        let folder = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let runner = TestGit.runner()
        _ = try await runner.run(.changing(["init", "--quiet"]), in: folder)

        // Act
        let result = try await runner.run(.reading(["rev-parse", "--show-toplevel"]), in: folder)

        // Assert
        #expect(result.status == 0)
        #expect(String(bytes: result.standardOutput, encoding: .utf8) == folder.path + "\n")
    }
}
