import Foundation
import Testing

struct LoginShellEnvironmentTests {
    private let marker = "MARKER"

    @Test
    func readsBetweenTheMarkersAndIgnoresWhatStartupFilesPrint() {
        // Arrange
        let output = Data("Welcome!\nMARKERPATH=/opt/homebrew/bin\0EDITOR=nova\0MARKERjob done\n".utf8)

        // Act
        let variables = LoginShellEnvironment.parse(output, marker: marker)

        // Assert
        #expect(variables == ["PATH": "/opt/homebrew/bin", "EDITOR": "nova"])
    }

    @Test
    func isIncompleteUntilTheClosingMarkerArrives() {
        // Arrange
        let output = Data("MARKERPATH=/opt/homebrew/bin\0EDI".utf8)

        // Act
        let variables = LoginShellEnvironment.parse(output, marker: marker)

        // Assert
        #expect(variables == nil)
    }

    @Test
    func keepsEqualsSignsInValuesAndDropsTheShellsOwnVariables() {
        // Arrange
        let output = Data("MARKERGREP_OPTIONS=--color=auto\0SHLVL=2\0PWD=/Users/me\0_=/usr/bin/env\0MARKER".utf8)

        // Act
        let variables = LoginShellEnvironment.parse(output, marker: marker)

        // Assert
        #expect(variables == ["GREP_OPTIONS": "--color=auto"])
    }

    @Test
    func capturesWhatALoginShellExports() async throws {
        // Arrange
        let home = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        try "export LOCUS_TEST_PROFILE=from-profile\n".write(
            to: home.appending(path: ".profile"),
            atomically: true,
            encoding: .utf8
        )
        let launchEnvironment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]

        // Act
        let captured = await LoginShellEnvironment.capture(
            shell: URL(filePath: "/bin/sh"),
            launchEnvironment: launchEnvironment
        )

        // Assert
        #expect(captured.source == .loginShell)
        #expect(captured.variables["LOCUS_TEST_PROFILE"] == "from-profile")
    }

    @Test
    func fallsBackToTheLaunchEnvironmentWhenTheShellHangs() async throws {
        // Arrange
        let folder = try TestGit.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let hangingShell = folder.appending(path: "hanging-shell")
        try "#!/bin/sh\nexec sleep 30\n".write(to: hangingShell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hangingShell.path)
        let launchEnvironment = ["PATH": "/usr/bin:/bin"]

        // Act
        let captured = await LoginShellEnvironment.capture(
            shell: hangingShell,
            launchEnvironment: launchEnvironment,
            timeout: .milliseconds(300)
        )

        // Assert
        #expect(captured.source == .launchEnvironment(because: .timedOut))
        #expect(captured.variables == launchEnvironment)
    }

    @Test
    func fallsBackToTheLaunchEnvironmentWhenTheShellIsMissing() async {
        // Arrange
        let launchEnvironment = ["PATH": "/usr/bin:/bin"]

        // Act
        let captured = await LoginShellEnvironment.capture(
            shell: URL(filePath: "/nonexistent/zsh"),
            launchEnvironment: launchEnvironment
        )

        // Assert
        #expect(captured.source == .launchEnvironment(because: .couldNotStart))
        #expect(captured.variables == launchEnvironment)
    }
}
