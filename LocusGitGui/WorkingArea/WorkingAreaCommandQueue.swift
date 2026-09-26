import AppKit
import os

/// Runs the working area's commands one after another, since two at once would fight over Git's
/// lock on the index, and a commit made straight after staging has to wait for the staging. Each
/// failure is shown as its own sheet with Git's words.
final class WorkingAreaCommandQueue {
    /// The file being staged changed after the diff showed it, so the lines picked in the diff are
    /// no longer the ones in the file.
    struct ChangedSinceShown: Error {}

    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "WorkingArea")

    /// Called after each command, whether it worked or not, since a failed one can still have
    /// changed something.
    var didRun: (() -> Void)?
    var presentFailure: ((GitFailure) -> Void)?
    private var last: Task<Void, Never>?

    /// `summary` says what failed, such as “Git couldn’t stage “README.md”.”
    func run(_ summary: String, _ command: @escaping () async throws -> Void) {
        let previous = last
        last = Task { [weak self] in
            await previous?.value
            do {
                try await command()
            } catch let failure as WorkingAreaStaging.Failure {
                self?.presentFailure?(GitFailure(summary: summary, arguments: failure.command.arguments, result: failure.result))
            } catch let failure as GitReadFailure {
                self?.presentFailure?(GitFailure(summary: summary, arguments: failure.command.arguments, result: failure.result))
            } catch let ChildProcess.Failure.couldNotStart(error) {
                self?.presentFailure?(GitFailure(
                    summary: summary,
                    arguments: [],
                    result: ChildProcess.Result(status: -1, standardOutput: Data(), standardError: Data(error.localizedDescription.utf8))
                ))
            } catch is ChangedSinceShown {
                NSSound.beep()
            } catch is CancellationError, is RepositoryCommandRunner.NoUsableGit {
                // Nothing to show: cancelled from the Activity window, or the app has said Git is gone.
            } catch {
                Self.log.error("A working area command failed: \(String(describing: type(of: error)), privacy: .public)")
            }
            self?.didRun?()
        }
    }

    /// For a change made without Git, such as moving an untracked file to the Trash, once the
    /// commands before it have run.
    func noteChange() {
        run("") {
            // Nothing to run. Waiting its turn is the point.
        }
    }

    /// Waits for every command queued so far.
    func finish() async {
        await last?.value
    }
}
