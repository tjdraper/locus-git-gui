import AppKit

/// Pushes a tag to a remote, or deletes it from one, which Push leaves alone since it pushes only
/// the branch.
final class RemoteTagWorkflow {
    /// Shows a failed command's sheet on the window it was started from.
    var present: ((GitFailure, NSWindow?, _ retry: (() -> Void)?, GitFailureNextSteps) -> Void)?
    var repositoryWindow: (() -> NSWindow?)?

    private let runner: RemoteOperationRunner
    private let queue: WorkingAreaCommandQueue

    init(runner: RemoteOperationRunner, queue: WorkingAreaCommandQueue) {
        self.runner = runner
        self.queue = queue
    }

    func push(_ tag: String, to remote: String, from window: NSWindow?) {
        run(
            RemoteCommand.pushTag(tag, to: remote),
            titled: "Pushing the tag “\(tag)” to “\(remote)”",
            failureSummary: "Git couldn’t push the tag “\(tag)” to “\(remote)”.",
            from: window
        ) { [weak self] in self?.push(tag, to: remote, from: window) }
    }

    /// Asks first. The tag stays in this repository, so pushing it again undoes it.
    func delete(_ tag: String, from remote: String, window: NSWindow?) {
        Task { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Delete the tag “\(tag)” from “\(remote)”?"
            alert.informativeText = "The tag stays in this repository, so pushing it again puts it back. "
                + "Anyone who has fetched it keeps their copy."
            alert.addButton(withTitle: "Delete from Remote")
            alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
            guard await AlertPresentation.run(alert, on: window ?? repositoryWindow?()) == .alertFirstButtonReturn else { return }
            run(
                RemoteCommand.deleteTag(tag, from: remote),
                titled: "Deleting the tag “\(tag)” from “\(remote)”",
                failureSummary: "Git couldn’t delete the tag “\(tag)” from “\(remote)”.",
                from: window
            ) { [weak self] in self?.delete(tag, from: remote, window: window) }
        }
    }

    private func run(
        _ command: GitCommand,
        titled title: String,
        failureSummary: String,
        from window: NSWindow?,
        retry: @escaping () -> Void
    ) {
        guard !runner.isBusy else {
            NSSound.beep()
            return
        }
        runner.reserve()
        queue.run("") { [weak self] in
            guard let self else { return }
            defer { runner.release() }
            let outcome = await runner.run(command, titled: title, failureSummary: failureSummary, from: window)
            if case let .failed(failure) = outcome {
                present?(failure, window, retry, GitFailureNextSteps())
            }
        }
    }
}
