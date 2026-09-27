import AppKit

/// Stashes changes and brings them back. A stash is named by its commit, which stays the same while
/// newer stashes renumber it. Dropping one asks first and names its commit, which Git keeps for a
/// while, so it can be stored back.
final class StashWorkflow {
    var context: () -> OperationContext = { OperationContext() }
    var repositoryWindow: () -> NSWindow? = { nil }
    var notice: ((OperationStatus.Notice) -> Void)?
    private let runner: OperationRunner

    init(runner: OperationRunner) {
        self.runner = runner
    }

    func stash(includingUntracked: Bool, from window: NSWindow?) {
        Task { [weak self] in
            guard let self, let window = window ?? repositoryWindow() else { return }
            let result = await FormSheet.ask(on: window) { finish in
                StashForm(includesUntracked: includingUntracked, finish: finish)
            }
            guard let result else { return }
            runner.perform(from: window) { steps in
                try await steps.run(
                    StashCommand.stash(message: result.message, includingUntracked: result.includesUntracked),
                    failing: "Git couldn’t stash the changes."
                )
            }
        }
    }

    func apply(_ commit: String, from window: NSWindow?) {
        let name = describe(commit)
        runner.perform(from: window) { steps in
            try await steps.run(StashCommand.apply(commit), failing: "Git couldn’t apply the stash \(name).")
        }
    }

    /// Git keeps the stash when its changes conflict, which the failure says.
    func pop(_ commit: String, from window: NSWindow?) {
        let name = describe(commit)
        runner.perform(from: window) { steps in
            guard let index = try await StashCommand.index(of: commit, running: steps.commands.run) else { return }
            try await steps.run(StashCommand.pop(at: index), failing: "Git couldn’t pop the stash \(name).")
        }
    }

    func drop(_ commit: String, from window: NSWindow?) {
        let entry = context().contents?.stashes.first { $0.id == .stash(commit) }
        let name = describe(commit)
        Task { [weak self] in
            guard let self else { return }
            let isConfirmed = await Confirmation.ask(
                "Drop the stash \(name)?",
                informativeText: "Its changes go from the stash list. Git keeps its commit, \(commit.prefix(7)), for a while, "
                    + "so it can be stored back with “git stash store \(commit.prefix(7))” until Git cleans up.",
                confirmTitle: "Drop",
                on: window ?? repositoryWindow()
            )
            guard isConfirmed else { return }
            runner.perform(from: window) { [weak self] steps in
                guard let index = try await StashCommand.index(of: commit, running: steps.commands.run) else { return }
                try await steps.run(StashCommand.drop(at: index), failing: "Git couldn’t drop the stash \(name).")
                self?.notice?(OperationStatus.Notice(
                    message: "Dropped the stash “\(entry?.message ?? commit)”. Its commit was \(commit.prefix(7)).",
                    hash: commit
                ))
            }
        }
    }

    private func describe(_ commit: String) -> String {
        context().contents?.stashes.first { $0.id == .stash(commit) }.map { "“\($0.message)”" } ?? String(commit.prefix(7))
    }
}
