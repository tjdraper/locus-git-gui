import AppKit

/// Checks out, creates, renames and deletes branches, and sets their upstreams. A checkout that
/// local changes are in the way of offers Stash and Continue, and a branch that isn't merged is
/// only deleted after saying how many commits it would leave without a branch.
final class BranchWorkflow {
    var context: () -> OperationContext = { OperationContext() }
    var repositoryWindow: () -> NSWindow? = { nil }
    /// After a branch is deleted, the commit it was at, which a new branch there brings back.
    var notice: ((OperationStatus.Notice) -> Void)?
    private let runner: OperationRunner

    init(runner: OperationRunner) {
        self.runner = runner
    }

    func checkOut(_ branch: String, from window: NSWindow?) {
        run(
            BranchCommand.checkOut(branch),
            purpose: "checking out “\(branch)”",
            failing: "Git couldn’t check out “\(branch)”.",
            from: window
        )
    }

    /// A tag or a commit, which leaves HEAD detached. `name` is how the user knows it, such as a
    /// tag's name or a short hash.
    func checkOutDetached(_ revision: String, named name: String, from window: NSWindow?) {
        run(
            BranchCommand.checkOutDetached(revision),
            purpose: "checking out \(name)",
            failing: "Git couldn’t check out \(name).",
            from: window
        )
    }

    /// Switches to the local branch that tracks it, or makes one. A local branch of the same name
    /// that tracks something else isn't taken over, so another name is asked for.
    func checkOut(remoteBranch id: SidebarItemID, from window: NSWindow?) {
        let context = context()
        guard case let .ref(fullName) = id, let (remote, branch) = context.remoteBranch(id) else { return }
        let short = "\(remote)/\(branch.name)"
        // The full name, since a local branch can be named like a remote one.
        let tracked = Revision(argument: fullName, name: short)
        switch RemoteBranchCheckout.plan(remoteBranch: fullName, remote: remote, nameOnRemote: branch.name, refs: context.refs) {
        case let .switchTo(local):
            checkOut(local, from: window)
        case let .create(name):
            checkOutTracking(tracked, as: name, from: window)
        case let .askForName(suggested):
            Task { [weak self] in
                guard let self, let window = window ?? repositoryWindow() else { return }
                let tracking = context.contents?.branches.first { $0.name == branch.name }?.upstream
                let reason = tracking.map { "tracks “\($0)”" } ?? "doesn’t track it"
                let result = await FormSheet.ask(on: window) { finish in
                    BranchNameForm(
                        title: "Check Out “\(short)”",
                        message: "There’s already a branch named “\(branch.name)”, which \(reason). "
                            + "Name the new branch that tracks “\(short)”.",
                        confirmTitle: "Check Out",
                        name: suggested,
                        takenNames: context.branchNames,
                        checksOut: nil,
                        finish: finish
                    )
                }
                guard let result else { return }
                checkOutTracking(tracked, as: result.name, from: window)
            }
        }
    }

    /// `start` is what Git starts it from, and `startTitle` how the sheet names it, such as
    /// “origin/main” or “1a2b3c4 (“Subject”)”.
    func newBranch(at start: String, startTitle: String, from window: NSWindow?) {
        Task { [weak self] in
            guard let self, let window = window ?? repositoryWindow() else { return }
            let result = await FormSheet.ask(on: window) { [context] finish in
                BranchNameForm(
                    title: "New Branch",
                    message: "Starts at \(startTitle).",
                    confirmTitle: "Create Branch",
                    name: "",
                    takenNames: context().branchNames,
                    checksOut: true,
                    finish: finish
                )
            }
            guard let result else { return }
            run(
                BranchCommand.create(result.name, at: start, checkingOut: result.checksOut),
                purpose: "checking out “\(result.name)”",
                failing: "Git couldn’t make the branch “\(result.name)”.",
                from: window
            )
        }
    }

    func rename(_ branch: String, from window: NSWindow?) {
        Task { [weak self] in
            guard let self, let window = window ?? repositoryWindow() else { return }
            let result = await FormSheet.ask(on: window) { [context] finish in
                BranchNameForm(
                    title: "Rename “\(branch)”",
                    message: nil,
                    confirmTitle: "Rename",
                    name: branch,
                    takenNames: context().branchNames.subtracting([branch]),
                    checksOut: nil,
                    finish: finish
                )
            }
            guard let result, result.name != branch else { return }
            runner.perform(from: window) { steps in
                try await steps.run(BranchCommand.rename(branch, to: result.name), failing: "Git couldn’t rename “\(branch)”.")
            }
        }
    }

    /// Asks first, naming the commit it's at, which a new branch there brings back.
    func delete(_ branch: String, from window: NSWindow?) {
        Task { [weak self] in
            guard let self else { return }
            let point = await RestorePoint.read("refs/heads/\(branch)", running: runner.commands.run)
            let isConfirmed = await Confirmation.ask(
                "Delete the branch “\(branch)”?",
                informativeText: point.map { "It’s at \($0.described). A new branch made there brings it back." }
                    ?? "A new branch made where it is brings it back.",
                confirmTitle: "Delete",
                on: window ?? repositoryWindow()
            )
            guard isConfirmed else { return }
            delete(branch, force: false, point: point, from: window)
        }
    }

    /// `upstream` is the remote branch's full name, and `name` its short one.
    func setUpstream(of branch: String, to upstream: String, named name: String, from window: NSWindow?) {
        runner.perform(from: window) { steps in
            try await steps.run(
                BranchCommand.setUpstream(of: branch, to: upstream),
                failing: "Git couldn’t make “\(name)” the upstream of “\(branch)”."
            )
        }
    }

    func unsetUpstream(of branch: String, from window: NSWindow?) {
        runner.perform(from: window) { steps in
            try await steps.run(BranchCommand.unsetUpstream(of: branch), failing: "Git couldn’t unset the upstream of “\(branch)”.")
        }
    }

    private func checkOutTracking(_ remoteBranch: Revision, as name: String, from window: NSWindow?) {
        run(
            BranchCommand.checkOutTracking(remoteBranch.argument, as: name),
            purpose: "checking out “\(remoteBranch.name)”",
            failing: "Git couldn’t check out “\(remoteBranch.name)”.",
            from: window
        )
    }

    /// A git branch -d that finds the branch isn't merged offers Delete Anyway, which asks again.
    private func delete(_ branch: String, force: Bool, point: RestorePoint?, from window: NSWindow?) {
        let nextSteps = { [weak self] (_: GitFailure) in
            GitFailureNextSteps(deleteAnyway: { self?.deleteAnyway(branch, point: point, from: window) })
        }
        runner.perform(from: window, nextSteps: nextSteps) { [weak self] steps in
            try await steps.run(BranchCommand.delete(branch, force: force), failing: "Git couldn’t delete the branch “\(branch)”.")
            if let point {
                self?.notice?(OperationStatus.Notice(
                    message: "“\(branch)” was at \(point.described) before it was deleted.",
                    hash: point.hash
                ))
            }
        }
    }

    private func deleteAnyway(_ branch: String, point: RestorePoint?, from window: NSWindow?) {
        Task { [weak self] in
            guard let self else { return }
            let count = await commitsOnlyOn(branch)
            let lost = switch count {
            case nil: "Commits only it has will be left without a branch."
            case 1: "1 commit on it isn’t on any other branch or tag, and will be left without a branch."
            case let count?: "\(count) commits on it aren’t on any other branch or tag, and will be left without a branch."
            }
            let isConfirmed = await Confirmation.ask(
                "Delete “\(branch)” anyway?",
                informativeText: lost + (point.map { " It’s at \($0.described), and a new branch made there brings them back." } ?? ""),
                confirmTitle: "Delete Anyway",
                on: window ?? repositoryWindow()
            )
            guard isConfirmed else { return }
            delete(branch, force: true, point: point, from: window)
        }
    }

    private func commitsOnlyOn(_ branch: String) async -> Int? {
        guard let result = try? await runner.commands.run(BranchCommand.commitsOnlyOn(branch)), result.status == 0 else { return nil }
        return String(bytes: result.standardOutput, encoding: .utf8).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Offers Stash and Continue when uncommitted changes are in the way.
    private func run(_ command: GitCommand, purpose: String, failing summary: String, from window: NSWindow?) {
        runner.perform(from: window, stashAndContinue: { [weak self] includesUntracked in
            self?.runStashing(command, includingUntracked: includesUntracked, purpose: purpose, failing: summary, from: window)
        }, body: { steps in
            try await steps.run(command, failing: summary)
        })
    }

    private func runStashing(
        _ command: GitCommand,
        includingUntracked: Bool,
        purpose: String,
        failing summary: String,
        from window: NSWindow?
    ) {
        runner.perform(from: window) { steps in
            try await LocalChangesStash.around(purpose, includingUntracked: includingUntracked, steps: steps) {
                try await steps.run(command, failing: summary)
            }
        }
    }
}
