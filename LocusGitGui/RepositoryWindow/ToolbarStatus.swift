import Foundation

/// What the window has to say: a fetch, pull or push running, an operation stopped partway, and the
/// notice a command that took something away leaves. The toolbar shows the latest, and the Notices
/// panel and window list them all. With none of them, the toolbar says when the repository last
/// fetched, so the status keeps its place rather than coming and going.
@Observable
final class ToolbarStatus {
    enum Entry: Equatable {
        case remoteRunning
        case stopped
        case remoteNotice
        case operationNotice
    }

    let remote: RemoteProgress
    let operation: OperationStatus

    init(remote: RemoteProgress, operation: OperationStatus) {
        self.remote = remote
        self.operation = operation
    }

    /// The latest first.
    var entries: [Entry] {
        var dated: [(entry: Entry, date: Date)] = []
        if let running = remote.running {
            dated.append((.remoteRunning, running.started))
        }
        if operation.stopped != nil {
            dated.append((.stopped, operation.stoppedSince ?? .distantPast))
        }
        if let notice = remote.notice {
            dated.append((.remoteNotice, notice.shown))
        }
        if let notice = operation.notice {
            dated.append((.operationNotice, notice.shown))
        }
        return dated.sorted { $0.date > $1.date }.map(\.entry)
    }

    var latest: Entry? {
        entries.first
    }

    /// Nil until the first refresh has read the remotes.
    func idleSummary(at now: Date) -> String? {
        guard let hasRemotes = remote.hasRemotes else { return nil }
        guard hasRemotes else { return "No remotes" }
        guard let lastFetched = remote.lastFetched else { return "Not fetched yet" }
        if now.timeIntervalSince(lastFetched) < 60 {
            return "Fetched just now"
        }
        return "Fetched \(RelativeDateTimeFormatter().localizedString(for: lastFetched, relativeTo: now))"
    }

    var lastFetchedDescription: String? {
        remote.lastFetched.map { "Last fetched \($0.formatted(date: .abbreviated, time: .shortened))" }
    }

    /// In a few words, for the toolbar's overflow menu and the icon's tooltip.
    func summary(of entry: Entry) -> String? {
        switch entry {
        case .remoteRunning: remote.running?.title
        case .stopped: operation.stopped?.title
        case .remoteNotice: remote.notice?.message
        case .operationNotice: operation.notice?.message
        }
    }
}
