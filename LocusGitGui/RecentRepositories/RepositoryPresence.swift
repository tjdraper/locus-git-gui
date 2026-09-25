import Foundation

/// Whether a repository on the recent list is still where it was, told from the file system alone
/// so every repository on the list can be checked each time the dashboard opens.
nonisolated enum RepositoryPresence: Equatable, Sendable {
    /// Or can't be told apart from present without running Git, such as when macOS privacy
    /// protection keeps the app out of its folder.
    case present
    /// Its folder or its Git directory is gone.
    case missing
    /// It's on a drive that isn't connected, so it may be back when the drive is.
    case driveNotConnected

    /// Off the caller's actor, since an unreachable network volume can take a long time to answer.
    @concurrent
    static func checkInBackground(_ repository: Repository) async -> RepositoryPresence {
        check(repository)
    }

    /// Blocks for as long as an unreachable network volume takes to answer.
    static func check(_ repository: Repository) -> RepositoryPresence {
        if isGone(repository.workTree) {
            return driveIsDisconnected(for: repository.workTree) ? .driveNotConnected : .missing
        }
        return isGone(repository.gitDirectory) ? .missing : .present
    }

    /// Only an answer that the path doesn't exist counts. Being refused access doesn't.
    private static func isGone(_ url: URL) -> Bool {
        var info = stat()
        guard stat(url.path, &info) != 0 else {
            return false
        }
        return errno == ENOENT || errno == ENOTDIR
    }

    private static func driveIsDisconnected(for url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        guard components.count > 2, components[1] == "Volumes" else {
            return false
        }
        return isGone(URL(filePath: "/Volumes/\(components[2])", directoryHint: .isDirectory))
    }
}
