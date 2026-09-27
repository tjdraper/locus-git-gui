import Foundation

/// The arguments to one `git` invocation, and whether it may change the repository.
nonisolated struct GitCommand: Sendable, Equatable {
    let arguments: [String]
    let isReadOnly: Bool
    /// What Git reads on its standard input, for a command that takes a list there. Nil gives it
    /// nothing to read.
    var input: Data?
    /// Where Git and SSH ask for a password, passphrase or answer while this command runs. Nil for
    /// a command that shouldn't ask, which then fails rather than waits.
    var askpass: AskpassChannel?
    /// Added to the environment Git runs with, such as the editor a rebase uses.
    var environment: [String: String] = [:]

    static func reading(_ arguments: [String]) -> GitCommand {
        GitCommand(arguments: arguments, isReadOnly: true)
    }

    static func changing(_ arguments: [String], input: Data? = nil) -> GitCommand {
        GitCommand(arguments: arguments, isReadOnly: false, input: input)
    }
}
