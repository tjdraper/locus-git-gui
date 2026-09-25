import Foundation
import Testing

struct GitLogEntryTests {
    private func entry(_ outcome: GitLogEntry.Outcome) -> GitLogEntry {
        GitLogEntry(
            startedAt: Date(timeIntervalSince1970: 1_800_000_000.25),
            executable: URL(filePath: "/opt/homebrew/bin/git"),
            arguments: ["status", "--porcelain=v2", "-z"],
            duration: .milliseconds(12),
            outcome: outcome
        )
    }

    @Test
    func machineReadableOutputIsShownOneRecordPerLine() {
        // Arrange
        let result = ChildProcess.Result(status: 0, standardOutput: Data("? a.txt\0? b.txt\0".utf8), standardError: Data())

        // Act
        let logged = entry(.exited(result))

        // Assert
        #expect(logged.output == "? a.txt\n? b.txt")
        #expect(logged.succeeded)
        #expect(logged.statusDescription == "exit 0")
    }

    @Test
    func theTranscriptHasTheCommandStatusAndDuration() {
        // Arrange
        let result = ChildProcess.Result(status: 128, standardOutput: Data(), standardError: Data("fatal: not a git repository\n".utf8))

        // Act
        let transcript = entry(.exited(result)).transcript

        // Assert
        #expect(transcript.hasSuffix("$ git status --porcelain=v2 -z  (exit 128, 12 ms)\nfatal: not a git repository"))
    }

    @Test
    func aSuccessKeepsLittleOutputAndSaysHowMuchWasLeftOut() {
        // Arrange
        let long = Data(repeating: UInt8(ascii: "x"), count: GitLogEntry.successfulOutputLimit + 10)
        let result = ChildProcess.Result(status: 0, standardOutput: long, standardError: Data())

        // Act
        let output = entry(.exited(result)).output

        // Assert
        #expect(output.hasSuffix("… (10 more bytes not kept)"))
    }

    @Test
    func aFailureKeepsFarMoreOutput() {
        // Arrange
        let long = Data(repeating: UInt8(ascii: "x"), count: GitLogEntry.successfulOutputLimit + 10)
        let result = ChildProcess.Result(status: 1, standardOutput: Data(), standardError: long)

        // Act
        let output = entry(.exited(result)).output

        // Assert
        #expect(output.count == long.count)
    }

    @Test
    func aCommandThatNeverStartedSaysWhy() {
        // Arrange
        let outcome = GitLogEntry.Outcome.couldNotStart("The file “git” doesn’t exist.")

        // Act
        let logged = entry(outcome)

        // Assert
        #expect(!logged.succeeded)
        #expect(logged.statusDescription == "didn’t start")
        #expect(logged.output == "The file “git” doesn’t exist.")
    }
}
