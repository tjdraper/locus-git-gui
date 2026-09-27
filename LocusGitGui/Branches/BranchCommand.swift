/// The Git commands that check out, create, rename and delete branches, and set their upstreams.
/// Branches are named without `refs/heads/`, as Git's branch commands take them.
nonisolated enum BranchCommand {
    static func checkOut(_ branch: String) -> GitCommand {
        .changing(["switch", "--no-guess", branch])
    }

    /// A tag or a commit, which leaves HEAD detached rather than on a branch.
    static func checkOutDetached(_ commit: String) -> GitCommand {
        .changing(["switch", "--detach", commit])
    }

    /// A local branch named `name` that tracks the remote branch, checked out.
    static func checkOutTracking(_ remoteBranch: String, as name: String) -> GitCommand {
        .changing(["switch", "--create", name, "--track", remoteBranch])
    }

    /// Git's `branch.autoSetupMerge` decides whether a branch made from a remote branch tracks it,
    /// as it does in Terminal.
    static func create(_ name: String, at start: String, checkingOut: Bool) -> GitCommand {
        checkingOut ? .changing(["switch", "--create", name, start]) : .changing(["branch", name, start])
    }

    static func rename(_ branch: String, to name: String) -> GitCommand {
        .changing(["branch", "--move", branch, name])
    }

    /// Without `force`, Git refuses a branch whose commits aren't merged into its upstream or HEAD.
    static func delete(_ branch: String, force: Bool) -> GitCommand {
        .changing(["branch", force ? "-D" : "-d", branch])
    }

    /// `upstream` is short, such as `origin/main`.
    static func setUpstream(of branch: String, to upstream: String) -> GitCommand {
        .changing(["branch", "--set-upstream-to=\(upstream)", branch])
    }

    static func unsetUpstream(of branch: String) -> GitCommand {
        .changing(["branch", "--unset-upstream", branch])
    }

    /// Commits only the branch has, which no other branch, remote branch or tag reaches, so deleting
    /// it leaves them without a name. `--exclude` applies to the `--branches` after it.
    static func commitsOnlyOn(_ branch: String) -> GitCommand {
        .reading(["rev-list", "--count", "refs/heads/\(branch)", "--not", "--remotes", "--tags", "--exclude=\(branch)", "--branches"])
    }
}
