import Foundation

/// Runs the user's chosen `git` in a repository, with their login shell's environment.
nonisolated struct GitRunner: Sendable {
    let executableURL: URL
    let environment: [String: String]

    func run(_ command: GitCommand, in directory: URL) async throws -> ChildProcess.Result {
        try await process(for: command, in: directory).run()
    }

    func stream(_ command: GitCommand, in directory: URL) -> AsyncThrowingStream<ChildProcess.Event, any Error> {
        process(for: command, in: directory).stream()
    }

    private func process(for command: GitCommand, in directory: URL) -> ChildProcess {
        ChildProcess(
            executableURL: executableURL,
            arguments: command.arguments,
            environment: GitEnvironment.variables(for: command, from: environment),
            currentDirectoryURL: directory
        )
    }
}
