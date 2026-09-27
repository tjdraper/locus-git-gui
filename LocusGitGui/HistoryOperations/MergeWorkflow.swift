import AppKit

/// Merges into a branch and rebases one onto another, from the Branch menu, the sidebar and a
/// branch dragged onto another. A branch that isn't checked out is checked out first. Stopping on
/// conflicts puts the window into that state, with Continue, Skip and Abort above the history.
final class MergeWorkflow {
    var context: () -> OperationContext = { OperationContext() }
    var repositoryWindow: () -> NSWindow? = { nil }
    private let runner: OperationRunner

    init(runner: OperationRunner) {
        self.runner = runner
    }

    /// `revision` as Git names it, such as `feature` or `origin/main`. `target` is checked out
    /// first when it's given.
    func merge(_ revision: String, into target: String? = nil, from window: NSWindow?) {
        let into = target.map { " into “\($0)”" } ?? ""
        let summary = "Git couldn’t merge “\(revision)”\(into)."
        perform(from: window, purpose: "merging “\(revision)”\(into)", nextToCheckOut: target) { steps, autostash in
            if let target {
                try await steps.run(BranchCommand.checkOut(target), failing: "Git couldn’t check out “\(target)” to merge into it.")
            }
            try await steps.run(HistoryOperationCommand.merge(revision, autostash: autostash), failing: summary)
        }
    }

    /// Rebases `branch`, or the checked-out branch when it's nil, onto `upstream`. Git checks
    /// `branch` out itself.
    func rebase(_ branch: String? = nil, onto upstream: String, from window: NSWindow?) {
        let name = (branch ?? context().checkedOutBranch).map { "“\($0)”" } ?? "HEAD"
        perform(from: window, purpose: "rebasing \(name) onto “\(upstream)”", nextToCheckOut: nil) { steps, autostash in
            try await steps.run(
                HistoryOperationCommand.rebase(onto: upstream, branch: branch, autostash: autostash),
                failing: "Git couldn’t rebase \(name) onto “\(upstream)”."
            )
        }
    }

    /// Uncommitted changes in the way offer Stash and Continue: Git's `--autostash`, which puts them
    /// back once the operation is finished, or around the whole thing when it checks out a branch
    /// first or untracked files are in the way, which `--autostash` leaves.
    private func perform(
        from window: NSWindow?,
        purpose: String,
        nextToCheckOut target: String?,
        _ body: @escaping (OperationRunner.Steps, _ autostash: Bool) async throws -> Void
    ) {
        runner.perform(from: window, stashAndContinue: { [weak self] includesUntracked in
            guard let self else { return }
            if includesUntracked || target != nil {
                runner.perform(from: window) { steps in
                    try await LocalChangesStash.around(purpose, includingUntracked: includesUntracked, steps: steps) {
                        try await body(steps, false)
                    }
                }
            } else {
                runner.perform(from: window) { steps in try await body(steps, true) }
            }
        }, body: { steps in
            try await body(steps, false)
        })
    }
}
