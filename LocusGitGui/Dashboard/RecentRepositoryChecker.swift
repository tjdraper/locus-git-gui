import Foundation

/// Checks the repositories on the recent list for the dashboard. Every repository gets a quick look
/// at the file system, for whether it's still there and its display name. Only the rows on screen
/// run Git for their branch, since the list can hold a thousand repositories.
final class RecentRepositoryChecker {
    /// What the file system says about one repository.
    struct Finding: Sendable {
        let repository: Repository
        let presence: RepositoryPresence
        /// Nil when it has none, or isn't there to read.
        let displayName: String?
    }

    /// Enough to fill a screen of rows quickly without starting dozens of Git processes at once.
    private static let concurrentChecks = 6

    var onScanned: (([Finding]) -> Void)?
    var onChecked: ((Repository, RecentRepositoryState) -> Void)?

    private let gitChoice: GitChoiceStore
    private let logs: GitCommandLogs
    private let checkForMissingGit: () -> Void
    private var visible: [String: Repository] = [:]
    /// Checked, or waiting to be, since the dashboard last came to the front.
    private var checkedThisRound: Set<String> = []
    private var waiting: [Repository] = []
    private var runningCount = 0
    private var scanning: Task<Void, Never>?

    init(gitChoice: GitChoiceStore, logs: GitCommandLogs, checkForMissingGit: @escaping () -> Void) {
        self.gitChoice = gitChoice
        self.logs = logs
        self.checkForMissingGit = checkForMissingGit
    }

    /// Starts over each time the dashboard comes to the front, since a repository can be moved,
    /// deleted or switched to another branch while it's behind something else.
    func startRound(with repositories: [Repository]) {
        checkedThisRound = []
        waiting = []
        scanning?.cancel()
        scanning = Task { [weak self] in
            let findings = await Self.scan(repositories)
            guard !Task.isCancelled else { return }
            self?.onScanned?(findings)
        }
        for repository in visible.values {
            request(repository)
        }
    }

    func stop() {
        waiting = []
        scanning?.cancel()
    }

    func rowAppeared(_ repository: Repository) {
        visible[repository.id] = repository
        request(repository)
    }

    /// A row scrolled away before its turn doesn't need checking any more.
    func rowDisappeared(_ repository: Repository) {
        visible[repository.id] = nil
        if let index = waiting.firstIndex(where: { $0.id == repository.id }) {
            waiting.remove(at: index)
            checkedThisRound.remove(repository.id)
        }
    }

    private func request(_ repository: Repository) {
        guard checkedThisRound.insert(repository.id).inserted else { return }
        waiting.append(repository)
        startWaitingChecks()
    }

    private func startWaitingChecks() {
        while runningCount < Self.concurrentChecks, !waiting.isEmpty {
            let repository = waiting.removeFirst()
            runningCount += 1
            Task {
                let state = await check(repository)
                runningCount -= 1
                if let state {
                    onChecked?(repository, state)
                }
                startWaitingChecks()
            }
        }
    }

    /// Nil when Git couldn't be run.
    private func check(_ repository: Repository) async -> RecentRepositoryState? {
        let commands = RepositoryCommandRunner(
            repository: repository,
            log: logs.log(for: repository),
            gitChoice: gitChoice,
            checkForMissingGit: checkForMissingGit
        )
        return try? await RecentRepositoryState.read(repository, running: commands.run)
    }

    @concurrent
    private static func scan(_ repositories: [Repository]) async -> [Finding] {
        repositories.map { repository in
            let presence = RepositoryPresence.check(repository)
            let displayName = presence == .present ? RepositoryDisplayName.read(from: repository.workTree).name : nil
            return Finding(repository: repository, presence: presence, displayName: displayName)
        }
    }
}
