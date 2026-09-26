import Foundation

/// The arguments to one `git` invocation, and whether it may change the repository.
nonisolated struct GitCommand: Sendable, Equatable {
    let arguments: [String]
    let isReadOnly: Bool
    /// What Git reads on its standard input, for a command that takes a list there. Nil gives it
    /// nothing to read.
    var input: Data?

    static func reading(_ arguments: [String]) -> GitCommand {
        GitCommand(arguments: arguments, isReadOnly: true)
    }

    static func changing(_ arguments: [String], input: Data? = nil) -> GitCommand {
        GitCommand(arguments: arguments, isReadOnly: false, input: input)
    }
}
