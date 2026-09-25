import Foundation

/// A Git command that failed, with everything needed to explain it: what the app was doing, the
/// command, and Git's own words, which are always shown in full.
nonisolated struct GitFailure: Equatable, Sendable {
    /// What failed, as a sentence the user can read without knowing Git's commands.
    let summary: String
    let arguments: [String]
    let result: ChildProcess.Result

    var recognized: RecognizedGitFailure? {
        RecognizedGitFailure.recognize(result)
    }

    /// Errors go to standard error, but some commands explain themselves on standard output, such
    /// as the list of conflicts a merge stops on.
    var output: String {
        [result.standardOutput, result.standardError]
            .compactMap { String(bytes: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var commandLine: String {
        GitCommandLine.display(arguments)
    }

    /// What Copy puts on the clipboard, for a bug report or a search.
    var transcript: String {
        """
        \(summary)

        $ \(commandLine)
        \(output.isEmpty ? "(Git printed nothing, and exited with status \(result.status).)" : output)
        """
    }
}
