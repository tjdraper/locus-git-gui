import Foundation

/// Runs Git in one repository and records every command in the repository's Git log.
final class RepositoryCommandRunner {
    /// There is no Git to run. The app's missing-Git notice tells the user, so callers stay quiet.
    struct NoUsableGit: Error {}

    let repository: Repository
    let log: GitCommandLog
    private let gitChoice: GitChoiceStore
    private let checkForMissingGit: () -> Void

    init(repository: Repository, log: GitCommandLog, gitChoice: GitChoiceStore, checkForMissingGit: @escaping () -> Void) {
        self.repository = repository
        self.log = log
        self.gitChoice = gitChoice
        self.checkForMissingGit = checkForMissingGit
    }

    func run(_ command: GitCommand) async throws -> ChildProcess.Result {
        guard let runner = await gitChoice.runner() else {
            throw NoUsableGit()
        }
        let startedAt = Date()
        let started = ContinuousClock.now
        func record(_ outcome: GitLogEntry.Outcome) {
            log.record(GitLogEntry(
                startedAt: startedAt,
                executable: runner.executableURL,
                arguments: command.arguments,
                duration: ContinuousClock.now - started,
                outcome: outcome
            ))
        }

        do {
            let result = try await runner.run(command, in: repository.workTree)
            record(.exited(result))
            return result
        } catch let ChildProcess.Failure.couldNotStart(error) {
            record(.couldNotStart(error.localizedDescription))
            // Git can fail to start because it's gone, or because the repository's folder is.
            guard await GitInstallation.isUsable(runner.executableURL, environment: runner.environment) else {
                checkForMissingGit()
                throw NoUsableGit()
            }
            throw ChildProcess.Failure.couldNotStart(error)
        } catch {
            record(.cancelled)
            throw error
        }
    }
}
