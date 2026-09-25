import Foundation
import Testing

struct GitFailureTests {
    private func failure(standardOutput: String = "", standardError: String = "", status: Int32 = 1) -> GitFailure {
        GitFailure(
            summary: "Git couldn't merge.",
            arguments: ["merge", "feature"],
            result: ChildProcess.Result(
                status: status,
                standardOutput: Data(standardOutput.utf8),
                standardError: Data(standardError.utf8)
            )
        )
    }

    @Test
    func theOutputKeepsBothStreams() {
        // Arrange
        let merge = failure(standardOutput: "CONFLICT (content): Merge conflict in a.txt\n", standardError: "error: could not apply\n")

        // Act
        let output = merge.output

        // Assert
        #expect(output == "CONFLICT (content): Merge conflict in a.txt\n\nerror: could not apply")
    }

    @Test
    func theTranscriptHasTheSummaryCommandAndOutput() {
        // Arrange
        let merge = failure(standardError: "fatal: refusing to merge unrelated histories\n", status: 128)

        // Act
        let transcript = merge.transcript

        // Assert
        #expect(transcript == """
        Git couldn't merge.

        $ git merge feature
        fatal: refusing to merge unrelated histories
        """)
    }

    @Test
    func silenceIsExplainedRatherThanLeftBlank() {
        // Arrange
        let silent = failure(status: 1)

        // Act
        let transcript = silent.transcript

        // Assert
        #expect(transcript.hasSuffix("(Git printed nothing, and exited with status 1.)"))
    }
}
