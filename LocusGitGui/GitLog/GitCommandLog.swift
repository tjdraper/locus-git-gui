import Foundation

/// Every command the app ran in one repository this session, newest first. It's how someone checks
/// what the app did, and what they paste into a bug report.
@Observable
final class GitCommandLog {
    /// Refreshes run all day, and only the recent past is useful when something goes wrong.
    private static let entryLimit = 1000

    private(set) var entries: [GitLogEntry] = []

    func record(_ entry: GitLogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.entryLimit {
            entries.removeLast(entries.count - Self.entryLimit)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Oldest first, the order the commands ran in.
    var transcript: String {
        entries.reversed().map(\.transcript).joined(separator: "\n\n")
    }
}
