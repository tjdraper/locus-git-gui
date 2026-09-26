import Foundation

/// Every command the app ran in one repository this session, newest first, and the ones still
/// running. It's how someone checks what the app is doing and did, and what they paste into a bug
/// report.
@Observable
final class GitCommandLog {
    struct RunningCommand: Identifiable {
        let id = UUID()
        let startedAt: Date
        let arguments: [String]
        let cancel: () -> Void

        var commandLine: String {
            GitCommandLine.display(arguments)
        }
    }

    /// Refreshes run all day, and only the recent past is useful when something goes wrong.
    private static let entryLimit = 1000

    private(set) var entries: [GitLogEntry] = []
    /// Oldest first, the order they started in.
    private(set) var running: [RunningCommand] = []

    func begin(_ arguments: [String], at startedAt: Date, cancel: @escaping () -> Void) -> UUID {
        let command = RunningCommand(startedAt: startedAt, arguments: arguments, cancel: cancel)
        running.append(command)
        return command.id
    }

    func end(_ id: UUID) {
        running.removeAll { $0.id == id }
    }

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
