import AppKit

/// Runs a command the user started that talks to a remote. The window's status shows how far it has
/// got, with Cancel, and a question Git or SSH asks goes to a sheet on the window it was
/// started from. One runs at a time.
final class RemoteOperationRunner {
    enum Outcome {
        case succeeded(ChildProcess.Result)
        case failed(GitFailure)
        /// Cancelled from the bar, a question's sheet or the Activity window, or Git is gone and the
        /// app has already said so.
        case stopped
    }

    let progress: RemoteProgress
    private let commands: RepositoryCommandRunner
    private let askpass: AskpassServer
    private var running: Task<ChildProcess.Result, any Error>?
    /// Commands started or waiting their turn. Every remote command is off until they're done, so
    /// a second click doesn't queue the same thing twice and only one talks to a remote at a time.
    private var reserved = 0 {
        // The toolbar's buttons are checked again on the next event, which a command finishing in
        // the background doesn't send.
        didSet { NSApp.setWindowsNeedUpdate(true) }
    }

    init(commands: RepositoryCommandRunner, askpass: AskpassServer, progress: RemoteProgress = RemoteProgress()) {
        self.commands = commands
        self.askpass = askpass
        self.progress = progress
    }

    /// `title` says what it's doing, such as “Fetching from “origin””, and `failureSummary` what
    /// failed, such as “Git couldn’t fetch from “origin”.”
    func run(_ command: GitCommand, titled title: String, failureSummary: String, from window: NSWindow?) async -> Outcome {
        let prompter = CredentialPrompter(
            activity: title,
            window: { [weak window] in window },
            cancelCommand: { [weak self] in self?.cancel() }
        )
        var command = command
        command.askpass = prompter.openChannel(on: askpass)
        defer { askpass.close(command.askpass) }
        progress.begin(title) { [weak self] in self?.cancel() }
        defer { progress.end() }
        let task = Task { [commands, progress, command] in
            try await commands.run(command) { progress.update($0) }
        }
        running = task
        defer { running = nil }
        do {
            let result = try await task.value
            guard result.status == 0 else {
                return .failed(GitFailure(summary: failureSummary, arguments: command.arguments, result: result))
            }
            return .succeeded(result)
        } catch let ChildProcess.Failure.couldNotStart(error) {
            // Git never ran, so there is no output of its own. The system's reason stands in for it.
            return .failed(GitFailure(
                summary: failureSummary,
                arguments: command.arguments,
                result: ChildProcess.Result(status: -1, standardOutput: Data(), standardError: Data(error.localizedDescription.utf8))
            ))
        } catch {
            return .stopped
        }
    }

    var isBusy: Bool {
        reserved > 0
    }

    /// From the moment the user asks, before the command waits its turn. Released once it's done.
    func reserve() {
        reserved += 1
    }

    func release() {
        reserved -= 1
    }

    func cancel() {
        running?.cancel()
    }
}
