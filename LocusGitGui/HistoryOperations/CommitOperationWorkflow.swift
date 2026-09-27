import AppKit

/// What can be done with one commit picked in the history: cherry-pick it onto the checked-out
/// branch, revert it, reset the branch to it, and reword or edit it. Rewording and editing rewrite
/// the branch from that commit on, so they ask first when it's already on the upstream.
final class CommitOperationWorkflow {
    var context: () -> OperationContext = { OperationContext() }
    var repositoryWindow: () -> NSWindow? = { nil }
    var notice: ((OperationStatus.Notice) -> Void)?
    /// Editing the last commit is Amend Last Commit in the working area, which this turns on.
    var amendLastCommit: (() -> Void)?
    /// Once an edit has stopped at its commit, where the changes are made.
    var goToUncommittedChanges: (() -> Void)?
    let ancestry: CheckedOutAncestry
    private let runner: OperationRunner

    init(runner: OperationRunner) {
        self.runner = runner
        ancestry = CheckedOutAncestry(run: runner.commands.run)
    }

    func cherryPick(_ commit: Commit, from window: NSWindow?) {
        let onto = context().checkedOutBranch.map { " onto “\($0)”" } ?? ""
        runStashingIfNeeded(
            HistoryOperationCommand.cherryPick(commit.hash, isMerge: commit.parents.count > 1),
            purpose: "cherry-picking \(commit.hash.prefix(7))",
            failing: "Git couldn’t cherry-pick \(Self.describe(commit))\(onto).",
            from: window
        )
    }

    func revert(_ commit: Commit, from window: NSWindow?) {
        runStashingIfNeeded(
            HistoryOperationCommand.revert(commit.hash, isMerge: commit.parents.count > 1),
            purpose: "reverting \(commit.hash.prefix(7))",
            failing: "Git couldn’t revert \(Self.describe(commit)).",
            from: window
        )
    }

    /// A hard reset asks first, since it throws away uncommitted changes. Every reset names the
    /// commit the branch was at afterwards, which a reset back to it brings back.
    func reset(to commit: Commit, mode: HistoryOperationCommand.ResetMode, from window: NSWindow?) {
        let context = context()
        let branch = context.checkedOutBranch.map { "“\($0)”" } ?? "HEAD"
        Task { [weak self] in
            guard let self else { return }
            let previous = await RestorePoint.read("HEAD", running: runner.commands.run)
            if mode == .hard {
                let thrownAway = context.hasTrackedChanges
                    ? " Uncommitted changes to tracked files are thrown away, and can’t be brought back. Untracked files stay."
                    : ""
                let isConfirmed = await Confirmation.ask(
                    "Hard reset \(branch) to \(Self.describe(commit))?",
                    informativeText: (previous.map { "\(branch) is at \($0.described) now, and a reset back to it brings it back." } ?? "")
                        + thrownAway,
                    confirmTitle: "Hard Reset",
                    on: window ?? repositoryWindow()
                )
                guard isConfirmed else { return }
            }
            runner.perform(from: window) { [weak self] steps in
                try await steps.run(
                    HistoryOperationCommand.reset(to: commit.hash, mode: mode),
                    failing: "Git couldn’t reset \(branch) to \(Self.describe(commit))."
                )
                if let previous, previous.hash != commit.hash {
                    self?.notice?(OperationStatus.Notice(
                        message: "Reset \(branch) to \(commit.hash.prefix(7)). It was at \(previous.described).",
                        hash: previous.hash
                    ))
                }
            }
        }
    }

    /// Why a commit can't be reworded or edited, or nil when it can. `isInCheckedOutHistory` is
    /// true when the history it was picked in is the checked-out branch's, which settles it.
    func rewriteProblem(_ commit: Commit, isInCheckedOutHistory: Bool) -> String? {
        let context = context()
        if let stopped = StoppedOperation(context.operation, branch: nil, conflicts: 0, editing: nil) {
            return "Finish or abort the \(stopped.kind.name) first."
        }
        guard let branch = context.checkedOutBranch else {
            return "Check out a branch first. HEAD is detached, so there’s no branch to rewrite."
        }
        // The last commit is amended, which works for a merge too.
        if commit.hash == context.head?.commit {
            return nil
        }
        if commit.parents.count > 1 {
            return "A merge commit can’t be reworded or edited here."
        }
        if isInCheckedOutHistory {
            return nil
        }
        switch ancestry.isOnCheckedOutBranch(commit.hash) {
        case true?: return nil
        case false?: return "Only a commit on “\(branch)” can be changed, since changing it rewrites the branch."
        case nil: return "Checking whether the commit is on “\(branch)”…"
        }
    }

    func reword(_ commit: Commit, from window: NSWindow?) {
        Task { [weak self] in
            guard let self, let window = window ?? repositoryWindow() else { return }
            let isLast = commit.hash == context().head?.commit
            guard let current = await message(of: commit) else {
                NSSound.beep()
                return
            }
            let later = isLast ? "" : " The commits after it are made again on top of it, with new hashes."
            let newMessage = await FormSheet.ask(on: window) { finish in
                RewordForm(message: "\(Self.describe(commit)).\(later)", current: current, finish: finish)
            }
            guard let newMessage, newMessage != current, await confirmRewriting(commit, from: window) else { return }
            if isLast {
                runner.perform(from: window) { steps in
                    try await steps.run(CommitRewrite.reword(message: newMessage.text), failing: "Git couldn’t reword the last commit.")
                }
            } else {
                rewrite(commit, from: window) { steps in
                    try await steps.run(
                        CommitRewrite.reword(message: newMessage.text),
                        failing: "Git couldn’t reword \(Self.describe(commit))."
                    )
                    try await steps.run(
                        HistoryOperationCommand.continueOperation(.rebase),
                        failing: "Git couldn’t make the commits after \(commit.hash.prefix(7)) again."
                    )
                }
            }
        }
    }

    /// Stops at the commit, with its changes in the working area to change and stage, until
    /// Continue carries them through the commits after it.
    func edit(_ commit: Commit, from window: NSWindow?) {
        guard commit.hash != context().head?.commit else {
            amendLastCommit?()
            return
        }
        Task { [weak self] in
            guard let self, await confirmRewriting(commit, from: window) else { return }
            rewrite(commit, from: window) { [weak self] _ in
                self?.goToUncommittedChanges?()
            }
        }
    }

    /// Starts the rebase that stops at the commit, then runs `atCommit` there. Local changes in the
    /// way offer Stash and Continue, which Git puts back when the rebase finishes.
    private func rewrite(_ commit: Commit, from window: NSWindow?, atCommit: @escaping (OperationRunner.Steps) async throws -> Void) {
        let gitDirectory = runner.commands.repository.gitDirectory
        let start = { (steps: OperationRunner.Steps, autostash: Bool) in
            try await steps.run(
                CommitRewrite.start(marking: commit.hash, parent: commit.parents.first, autostash: autostash),
                failing: "Git couldn’t start rewriting the branch from \(Self.describe(commit))."
            )
            guard StoppedOperation.editedCommit(gitDirectory: gitDirectory) == commit.hash else { return }
            try await atCommit(steps)
        }
        runner.perform(from: window, stashAndContinue: { [weak self] _ in
            self?.runner.perform(from: window) { steps in try await start(steps, true) }
        }, body: { steps in
            try await start(steps, false)
        })
    }

    /// Asks when the commit is already on the upstream, since the branch will need a force push.
    private func confirmRewriting(_ commit: Commit, from window: NSWindow?) async -> Bool {
        guard let upstream = context().head?.upstream,
              let result = try? await runner.commands.run(HistoryOperationCommand.isAncestor(commit.hash, of: "@{upstream}")),
              result.status == 0
        else { return true }
        return await Confirmation.ask(
            "The commit “\(commit.subject)” is already on “\(upstream)”.",
            informativeText: "Changing it rewrites the branch from there on, so pushing it will need a force push, "
                + "and anyone who has the old commits will have to bring their work across.",
            confirmTitle: "Continue",
            on: window ?? repositoryWindow()
        )
    }

    private func message(of commit: Commit) async -> CommitMessage? {
        let command = CommitDetail.messageCommand(commit.hash)
        let text = try? await GitReadFailure.read("commit message", with: command, running: runner.commands.run) {
            try UnreadableGitOutput.text($0)
        }
        return text.map(CommitMessage.init(parsing:))
    }

    /// Cherry-pick and revert have no `--autostash`, so Stash and Continue puts the changes aside
    /// around them, and leaves them in the stash list when the command stops on conflicts.
    private func runStashingIfNeeded(_ command: GitCommand, purpose: String, failing summary: String, from window: NSWindow?) {
        runner.perform(from: window, stashAndContinue: { [weak self] includesUntracked in
            self?.runner.perform(from: window) { steps in
                try await LocalChangesStash.around(purpose, includingUntracked: includesUntracked, steps: steps) {
                    try await steps.run(command, failing: summary)
                }
            }
        }, body: { steps in
            try await steps.run(command, failing: summary)
        })
    }

    /// “1a2b3c4 (“Subject”)”, for a sentence.
    static func describe(_ commit: Commit) -> String {
        "\(commit.hash.prefix(7)) (“\(commit.subject)”)"
    }
}
