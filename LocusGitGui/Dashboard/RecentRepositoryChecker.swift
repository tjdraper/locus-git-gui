import Foundation

/// Checks each repository on the recent list for the dashboard, recording what it runs in that
/// repository's Git log.
final class RecentRepositoryChecker {
    /// Enough to fill a screen of rows quickly without starting a hundred Git processes at once.
    private static let concurrentChecks = 6

    private let gitChoice: GitChoiceStore
    private let logs: GitCommandLogs
    private let checkForMissingGit: () -> Void

    init(gitChoice: GitChoiceStore, logs: GitCommandLogs, checkForMissingGit: @escaping () -> Void) {
        self.gitChoice = gitChoice
        self.logs = logs
        self.checkForMissingGit = checkForMissingGit
    }

    /// Reports each repository as its check finishes, in the order given as far as the checks allow.
    /// A repository Git couldn't be run for isn't reported.
    func check(_ repositories: [Repository], report: (Repository, RecentRepositoryState) -> Void) async {
        await withTaskGroup(of: (Repository, RecentRepositoryState?).self) { group in
            var waiting = repositories[...]
            for next in waiting.prefix(Self.concurrentChecks) {
                group.addTask { (next, await self.check(next)) }
            }
            waiting = waiting.dropFirst(Self.concurrentChecks)
            for await (repository, state) in group {
                if let state {
                    report(repository, state)
                }
                if let next = waiting.popFirst() {
                    group.addTask { (next, await self.check(next)) }
                }
            }
        }
    }

    private func check(_ repository: Repository) async -> RecentRepositoryState? {
        let commands = RepositoryCommandRunner(
            repository: repository,
            log: logs.log(for: repository),
            gitChoice: gitChoice,
            checkForMissingGit: checkForMissingGit
        )
        return try? await RecentRepositoryState.read(repository, running: commands.run)
    }
}
