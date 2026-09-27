import Foundation
import os

/// A refresh that failed, as the toolbar's warning explains it.
struct RefreshFailure {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "RepositoryWindow")

    let failure: GitFailure
    /// The status couldn't be read, so the title bar's branch and state can't be trusted.
    let makesStatusUnavailable: Bool

    /// Nil for what isn't shown: a refresh a newer one cancelled, a Git that's gone, which the
    /// app's own notice covers, and anything unexpected, which is logged.
    init?(_ error: any Error) {
        switch error {
        case is CancellationError, is RepositoryCommandRunner.NoUsableGit:
            return nil
        case let failure as GitReadFailure:
            makesStatusUnavailable = failure.command == RepositoryStatus.command
            self.failure = GitFailure(
                summary: failure.outputWasUnreadable
                    ? "Locus Git Gui couldn’t read Git’s report on this repository’s \(failure.subject)."
                    : "Git couldn’t read this repository’s \(failure.subject).",
                arguments: failure.command.arguments,
                result: failure.result
            )
        case let ChildProcess.Failure.couldNotStart(error):
            // Git never ran, so there is no output of its own. The system's reason stands in for it.
            makesStatusUnavailable = true
            failure = GitFailure(
                summary: "Git couldn’t start in this repository’s folder.",
                arguments: RepositoryStatus.command.arguments,
                result: ChildProcess.Result(status: -1, standardOutput: Data(), standardError: Data(error.localizedDescription.utf8))
            )
        default:
            Self.log.error("Refresh failed: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }
}
