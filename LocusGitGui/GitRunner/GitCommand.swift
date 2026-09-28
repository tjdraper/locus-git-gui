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
    /// Changes only what Git keeps for itself, such as a cache, and nothing the user sees, so it
    /// runs while the app is read-only after the trial.
    var isHousekeeping = false

    static func reading(_ arguments: [String]) -> GitCommand {
        GitCommand(arguments: arguments, isReadOnly: true)
    }

    static func changing(_ arguments: [String], input: Data? = nil) -> GitCommand {
        GitCommand(arguments: arguments, isReadOnly: false, input: input)
    }

    static func housekeeping(_ arguments: [String]) -> GitCommand {
        GitCommand(arguments: arguments, isReadOnly: false, isHousekeeping: true)
    }
}
