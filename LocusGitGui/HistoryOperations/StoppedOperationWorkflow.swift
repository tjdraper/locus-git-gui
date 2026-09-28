import AppKit

/// Continue, Skip and Abort for a merge, rebase, cherry-pick or revert that stopped partway, from
/// the window's status and the Commit menu. Continuing a merge commits it with the message
/// written in the working area, or Git's own when that's empty.
final class StoppedOperationWorkflow {
    var context: () -> OperationContext = { OperationContext() }
    var repositoryWindow: () -> NSWindow? = { nil }
    private let runner: OperationRunner
    private let editor: CommitMessageEditor

    init(runner: OperationRunner, editor: CommitMessageEditor) {
        self.runner = runner
        self.editor = editor
    }

    var stopped: StoppedOperation? {
        let context = context()
        return StoppedOperation(context.operation, branch: context.checkedOutBranch, conflicts: context.conflicts, editing: nil)
    }

    /// A rebase detaches HEAD while it works, so the branch is named by the rebase.
    private var rebasedBranch: String? {
        let context = context()
        if case let .rebasing(branch?, _, _) = context.operation {
            return branch
        }
        return context.checkedOutBranch
    }

    func continueOperation(from window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window ?? repositoryWindow()) else { return }
        guard let kind = stopped?.kind else {
            NSSound.beep()
            return
        }
        let message = kind == .merge && !editor.isAmending ? editor.message : CommitMessage()
        let summary = "Git couldn’t continue the \(kind.name)."
        runner.perform(from: window) { [weak self] steps in
            try await steps.run(HistoryOperationCommand.continueOperation(kind, message: message.text), failing: summary)
            if !message.isEmpty, self?.editor.message == message {
                self?.editor.finishCommitting()
            }
        }
    }

    func skip(from window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window ?? repositoryWindow()) else { return }
        guard let kind = stopped?.kind, let command = HistoryOperationCommand.skip(kind) else {
            NSSound.beep()
            return
        }
        runner.perform(from: window) { steps in
            try await steps.run(command, failing: "Git couldn’t skip the commit.")
        }
    }

    /// Asks first, since conflicts already resolved are lost.
    func abort(from window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window ?? repositoryWindow()) else { return }
        guard let kind = stopped?.kind else {
            NSSound.beep()
            return
        }
        let branch = rebasedBranch.map { "“\($0)”" } ?? "The branch"
        let backTo = switch kind {
        case .merge: "The files go back to how they were before the merge started."
        case .rebase: "\(branch) goes back to where it was before the rebase started."
        case .cherryPick, .revert: "\(branch) goes back to where it was before the \(kind.name) started."
        }
        Task { [weak self] in
            let isConfirmed = await Confirmation.ask(
                "Abort the \(kind.name)?",
                informativeText: "\(backTo) Conflicts resolved so far are lost.",
                confirmTitle: "Abort",
                on: window ?? self?.repositoryWindow()
            )
            guard isConfirmed, let self else { return }
            runner.perform(from: window) { steps in
                try await steps.run(HistoryOperationCommand.abort(kind), failing: "Git couldn’t abort the \(kind.name).")
            }
        }
    }
}
