import Foundation

/// A Git operation that stopped partway and is waiting for the user, read from the files Git
/// keeps in the Git directory while one is underway. `git status` doesn't report these in any
/// machine-readable form.
nonisolated enum InProgressOperation: Equatable, Sendable {
    /// `step` and `total` are nil when Git hasn't written them yet.
    case rebasing(branch: String?, step: Int?, total: Int?)
    case merging
    case cherryPicking
    case reverting
    case bisecting

    static func read(gitDirectory: URL) -> InProgressOperation? {
        // The merge backend, which `rebase` uses by default.
        let rebaseMerge = gitDirectory.appending(path: "rebase-merge")
        if exists(rebaseMerge) {
            return .rebasing(
                branch: branchName(in: rebaseMerge),
                step: number(in: rebaseMerge.appending(path: "msgnum")),
                total: number(in: rebaseMerge.appending(path: "end"))
            )
        }
        // The apply backend, which `git am` shares. `applying` marks an `am` rather than a rebase.
        let rebaseApply = gitDirectory.appending(path: "rebase-apply")
        if exists(rebaseApply), !exists(rebaseApply.appending(path: "applying")) {
            return .rebasing(
                branch: branchName(in: rebaseApply),
                step: number(in: rebaseApply.appending(path: "next")),
                total: number(in: rebaseApply.appending(path: "last"))
            )
        }
        if exists(gitDirectory.appending(path: "MERGE_HEAD")) {
            return .merging
        }
        if exists(gitDirectory.appending(path: "CHERRY_PICK_HEAD")) {
            return .cherryPicking
        }
        if exists(gitDirectory.appending(path: "REVERT_HEAD")) {
            return .reverting
        }
        if exists(gitDirectory.appending(path: "BISECT_LOG")) {
            return .bisecting
        }
        return nil
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func contents(of url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(in url: URL) -> Int? {
        contents(of: url).flatMap { Int($0) }
    }

    /// `head-name` holds the full ref, or `detached HEAD` when the rebase started from one.
    private static func branchName(in folder: URL) -> String? {
        guard let headName = contents(of: folder.appending(path: "head-name")), headName.hasPrefix("refs/heads/") else {
            return nil
        }
        return String(headName.dropFirst("refs/heads/".count))
    }
}
