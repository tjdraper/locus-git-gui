import Foundation

/// A command that reads the repository failed, or wrote something that couldn't be read. Git's
/// output is kept whole, since it is the part people can search for.
nonisolated struct GitReadFailure: Error, Equatable {
    /// What was being read, worded to follow "this repository’s", such as "status".
    let subject: String
    let command: GitCommand
    let result: ChildProcess.Result
    let outputWasUnreadable: Bool

    static func read<Value>(
        _ subject: String,
        with command: GitCommand,
        running run: (GitCommand) async throws -> ChildProcess.Result,
        parse: (Data) throws -> Value
    ) async throws -> Value {
        let result = try await run(command)
        guard result.status == 0 else {
            throw GitReadFailure(subject: subject, command: command, result: result, outputWasUnreadable: false)
        }
        do {
            return try parse(result.standardOutput)
        } catch {
            throw GitReadFailure(subject: subject, command: command, result: result, outputWasUnreadable: true)
        }
    }
}
