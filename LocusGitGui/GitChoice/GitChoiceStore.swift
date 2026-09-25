import Foundation

/// The Git the app runs, what else is installed, and the user's choice between them, for the
/// checklist's Git step and anything that needs to know whether Git can run.
@Observable
final class GitChoiceStore {
    enum Rejection: Equatable {
        case notAFullPath
        case probeFailed(GitInstallation.ProbeFailure)
    }

    /// Nil until first checked.
    private(set) var availability: GitChoice.Availability?
    /// The chosen Git's version, once it has answered.
    private(set) var chosenInstallation: GitInstallation?
    /// Nil while searching.
    private(set) var searchResult: GitFinder.Result?
    private(set) var rejectedChoice: Rejection?

    /// Lets folders the user asked to open before choosing a Git open once they have.
    @ObservationIgnored var onGitChosen: (() -> Void)?

    private let loginShell: Task<LoginShellEnvironment, Never>
    private let choice = GitChoice()

    init(loginShell: Task<LoginShellEnvironment, Never>) {
        self.loginShell = loginShell
    }

    @discardableResult
    func checkAvailability() async -> GitChoice.Availability {
        let environment = await loginShell.value.variables
        let availability = await choice.availability { await GitInstallation.isUsable($0, environment: environment) }
        self.availability = availability
        return availability
    }

    /// Nil when there is no usable Git to run.
    func runner() async -> GitRunner? {
        let environment = await loginShell.value.variables
        guard case let .available(url) = await checkAvailability() else {
            return nil
        }
        return GitRunner(executableURL: url, environment: environment)
    }

    /// Checks the chosen Git and searches again, since either can change while the checklist is
    /// open, such as when the Command Line Tools finish installing.
    func refresh() async {
        let environment = await loginShell.value.variables
        if case let .available(url) = await checkAvailability() {
            chosenInstallation = try? await GitInstallation.probe(url, environment: environment)
        } else {
            chosenInstallation = nil
        }
        searchResult = await GitFinder.find(environment: environment)
    }

    func choose(_ installation: GitInstallation) {
        choice.executableURL = installation.executableURL
        availability = .available(installation.executableURL)
        chosenInstallation = installation
        rejectedChoice = nil
        onGitChosen?()
    }

    /// Returns whether the file turned out to be Git and is now the one in use.
    @discardableResult
    func choose(fileAt url: URL) async -> Bool {
        let environment = await loginShell.value.variables
        do {
            choose(try await GitInstallation.probe(url, environment: environment))
            return true
        } catch {
            rejectedChoice = .probeFailed(error)
            return false
        }
    }

    @discardableResult
    func choose(typedPath: String) async -> Bool {
        guard let url = TypedGitPath.url(from: typedPath) else {
            rejectedChoice = .notAFullPath
            return false
        }
        return await choose(fileAt: url)
    }

    func dismissRejection() {
        rejectedChoice = nil
    }

    /// Opens Apple's installer, which runs in its own window. The step searches again when the
    /// user comes back to the app.
    func installCommandLineTools() {
        let installer = ChildProcess(
            executableURL: URL(filePath: "/usr/bin/xcode-select"),
            arguments: ["--install"],
            environment: [:],
            currentDirectoryURL: nil
        )
        Task {
            _ = try? await installer.run()
        }
    }
}
