import Foundation

/// What the window has to say: a fetch, pull or push running, an operation stopped partway, the
/// notice a command that took something away leaves, an update to the app waiting, and the trial
/// running out. The toolbar shows the latest, and the Notices
/// panel and window list them all. With none of them, the toolbar says when the repository last
/// fetched, so the status keeps its place rather than coming and going.
@Observable
final class ToolbarStatus {
    enum Entry: Equatable {
        case remoteRunning
        case stopped
        case remoteNotice
        case operationNotice
        case update
        case trial
    }

    let remote: RemoteProgress
    let operation: OperationStatus
    let updates: UpdateAvailability
    let entitlements: EntitlementStore

    init(
        remote: RemoteProgress,
        operation: OperationStatus,
        updates: UpdateAvailability = .shared,
        entitlements: EntitlementStore = .shared
    ) {
        self.remote = remote
        self.operation = operation
        self.updates = updates
        self.entitlements = entitlements
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
        if updates.isAvailable {
            dated.append((.update, updates.found ?? .distantPast))
        }
        // Last, since it's there for the whole trial, and every other notice is news.
        if entitlements.notice != nil {
            dated.append((.trial, .distantPast))
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
        case .update: updateMessage
        case .trial: entitlements.notice?.message
        }
    }

    var updateMessage: String? {
        updates.version.map { "Version \($0) is ready." }
    }
}
