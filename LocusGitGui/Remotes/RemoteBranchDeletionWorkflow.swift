import AppKit

/// Deletes a branch from a remote, as `RemoteTagWorkflow` does a tag. It asks first and names the
/// commit the branch was at, which this repository keeps, so it can be pushed back.
final class RemoteBranchDeletionWorkflow {
    /// Shows a failed command's sheet on the window it was started from.
    var present: ((GitFailure, NSWindow?, _ retry: (() -> Void)?, GitFailureNextSteps) -> Void)?
    var repositoryWindow: (() -> NSWindow?)?

    private let runner: RemoteOperationRunner
    private let commands: RepositoryCommandRunner
    private let queue: WorkingAreaCommandQueue

    init(runner: RemoteOperationRunner, commands: RepositoryCommandRunner, queue: WorkingAreaCommandQueue) {
        self.runner = runner
        self.commands = commands
        self.queue = queue
    }

    /// `branch` is its name on the remote, such as `feature`.
    func delete(_ branch: String, from remote: String, window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window ?? repositoryWindow?()) else { return }
        Task { [weak self] in
            guard let self else { return }
            let point = await RestorePoint.read("refs/remotes/\(remote)/\(branch)", running: commands.run)
            let local = "A local branch named “\(branch)” stays as it is."
            let isConfirmed = await Confirmation.ask(
                "Delete “\(branch)” from “\(remote)”?",
                informativeText: (point.map { "It’s at \($0.described), which this repository keeps, so it can be pushed back. " } ?? "")
                    + local + " Anyone who has fetched it keeps their copy until they prune.",
                confirmTitle: "Delete from Remote",
                on: window ?? repositoryWindow?()
            )
            guard isConfirmed else { return }
            guard !runner.isBusy else {
                NSSound.beep()
                return
            }
            runner.reserve()
            queue.run("") { [weak self] in
                guard let self else { return }
                defer { runner.release() }
                let outcome = await runner.run(
                    RemoteCommand.deleteBranch(branch, from: remote),
                    titled: "Deleting “\(branch)” from “\(remote)”",
                    failureSummary: "Git couldn’t delete “\(branch)” from “\(remote)”.",
                    from: window
                )
                switch outcome {
                case .succeeded:
                    if let point {
                        runner.progress.show(RemoteProgress.Notice(
                            message: "“\(branch)” was at \(point.described) on “\(remote)” before it was deleted. "
                                + "This repository still has it.",
                            hash: point.hash
                        ))
                    }
                case let .failed(failure):
                    present?(failure, window, { [weak self] in self?.delete(branch, from: remote, window: window) }, GitFailureNextSteps())
                case .stopped:
                    break
                }
            }
        }
    }
}
