/// The Git commands that talk to remotes or change them. Each that talks to a remote asks for
/// `--progress`, which Git otherwise leaves out when it isn't writing to a terminal.
nonisolated enum RemoteCommand {
    enum PullStrategy: Sendable {
        case merge
        case rebase
    }

    /// Every remote, as the sidebar lists every remote's branches.
    static func fetchAll(_ options: FetchOptions = FetchOptions()) -> GitCommand {
        .changing(["fetch", "--all", "--progress"] + options.arguments)
    }

    /// Only ever updates remote-tracking branches, so nothing the user works on moves by itself:
    /// no tags, no `FETCH_HEAD`, no submodules, and no maintenance started afterwards. Pruning
    /// removes only remote-tracking branches too, so it follows Fetch's option.
    static func automaticFetch(prunes: Bool) -> GitCommand {
        let arguments = ["fetch", "--all", "--no-tags", "--no-write-fetch-head", "--recurse-submodules=no", "--no-auto-gc"]
        return .changing(arguments + (prunes ? ["--prune"] : []))
    }

    static let push = GitCommand.changing(["push", "--progress"])

    /// Replaces the remote's branch only while it's still where this repository last saw it.
    static let forcePush = GitCommand.changing(["push", "--progress", "--force-with-lease"])

    static let defaultPushRemote = GitCommand.reading(["config", "--get", "remote.pushDefault"])

    static func fetch(_ remote: String, _ options: FetchOptions = FetchOptions()) -> GitCommand {
        .changing(["fetch", "--progress"] + options.arguments + [remote])
    }

    /// Nil follows the repository's own configuration, which is what a pull in Terminal does.
    static func pull(_ strategy: PullStrategy? = nil) -> GitCommand {
        switch strategy {
        case nil: .changing(["pull", "--progress"])
        case .merge: .changing(["pull", "--progress", "--no-rebase"])
        case .rebase: .changing(["pull", "--progress", "--rebase"])
        }
    }

    /// Kept in the repository's own configuration, where `git pull` in Terminal reads it too.
    static func rememberPullStrategy(_ strategy: PullStrategy) -> GitCommand {
        .changing(["config", "pull.rebase", strategy == .rebase ? "true" : "false"])
    }

    /// For a branch with no upstream yet, which the push sets to the branch of the same name.
    static func pushSettingUpstream(branch: String, to remote: String) -> GitCommand {
        .changing(["push", "--progress", "--set-upstream", remote, "refs/heads/\(branch):refs/heads/\(branch)"])
    }

    static func pushRemote(of branch: String) -> GitCommand {
        .reading(["config", "--get", "branch.\(branch).pushRemote"])
    }

    static func pushTag(_ tag: String, to remote: String) -> GitCommand {
        .changing(["push", "--progress", remote, "refs/tags/\(tag)"])
    }

    static func deleteTag(_ tag: String, from remote: String) -> GitCommand {
        .changing(["push", "--progress", remote, "--delete", "refs/tags/\(tag)"])
    }

    /// Also removes this repository's remote-tracking branch for it.
    static func deleteBranch(_ branch: String, from remote: String) -> GitCommand {
        .changing(["push", "--progress", remote, "--delete", "refs/heads/\(branch)"])
    }

    static func addRemote(_ name: String, url: String) -> GitCommand {
        .changing(["remote", "add", name, url])
    }

    static func renameRemote(_ name: String, to newName: String) -> GitCommand {
        .changing(["remote", "rename", name, newName])
    }

    static func setURL(of remote: String, to url: String) -> GitCommand {
        .changing(["remote", "set-url", remote, url])
    }

    static func removeRemote(_ name: String) -> GitCommand {
        .changing(["remote", "remove", name])
    }

    static func url(of remote: String) -> GitCommand {
        .reading(["remote", "get-url", remote])
    }

    /// Run in the folder the clone goes in, making `folder` there. Submodules come too, since a
    /// checkout missing them usually doesn't build.
    static func clone(_ address: String, into folder: String, includingSubmodules: Bool) -> GitCommand {
        .changing(["clone", "--progress"] + (includingSubmodules ? ["--recurse-submodules"] : []) + ["--", address, folder])
    }

    /// Commits on the upstream that the checked-out branch doesn't have, which a force push would
    /// take off the remote.
    static let upstreamOnlyCount = GitCommand.reading(["rev-list", "--count", "HEAD..@{upstream}"])

    /// How far the branch and its upstream have each moved on: the branch's count, then the upstream's.
    static let divergence = GitCommand.reading(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
}
