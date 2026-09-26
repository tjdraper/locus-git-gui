import Foundation

/// Each repository's activity. Kept for the session rather than with a window, so reopening a
/// repository still shows what ran before, including what the dashboard ran while checking it.
final class GitCommandLogs {
    private var logs: [String: GitCommandLog] = [:]

    func log(for repository: Repository) -> GitCommandLog {
        if let log = logs[repository.id] {
            return log
        }
        let log = GitCommandLog()
        logs[repository.id] = log
        return log
    }
}
