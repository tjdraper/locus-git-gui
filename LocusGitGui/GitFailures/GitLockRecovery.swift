import Foundation

/// Decides whether a lock Git left behind can safely go, and removes it.
nonisolated enum GitLockRecovery {
    enum State: Equatable, Sendable {
        /// Already gone, so there is nothing to remove.
        case gone
        case inUse(processes: [pid_t])
        /// Nothing is running that could hold it, so a Git process crashed and left it.
        case abandoned(since: Date?)
    }

    enum RemovalFailure: Error, Equatable {
        case notALockInThisRepository
        case inUse
    }

    static func state(of lock: URL, in repository: Repository) -> State {
        guard FileManager.default.fileExists(atPath: lock.path) else {
            return .gone
        }
        let processes = GitProcessFinder.processes(workingIn: [repository.workTree, repository.gitDirectory])
        guard processes.isEmpty else {
            return .inUse(processes: processes)
        }
        let modified = try? FileManager.default.attributesOfItem(atPath: lock.path)[.modificationDate] as? Date
        return .abandoned(since: modified)
    }

    /// Checks again right before removing, since a Git process may have started since the user
    /// was last told it was safe.
    static func remove(_ lock: URL, in repository: Repository) throws {
        guard isLock(lock, in: repository) else {
            throw RemovalFailure.notALockInThisRepository
        }
        switch state(of: lock, in: repository) {
        case .gone:
            return
        case .inUse:
            throw RemovalFailure.inUse
        case .abandoned:
            try FileManager.default.removeItem(at: lock)
        }
    }

    /// The path comes from Git's output, so it is checked before anything is deleted: it has to be
    /// a lock file inside this repository.
    private static func isLock(_ lock: URL, in repository: Repository) -> Bool {
        let path = ResolvedPath.of(lock.deletingLastPathComponent()).path + "/" + lock.lastPathComponent
        let roots = [repository.gitDirectory, repository.workTree].map { ResolvedPath.of($0).path + "/" }
        return lock.pathExtension == "lock" && roots.contains { path.hasPrefix($0) }
    }
}
