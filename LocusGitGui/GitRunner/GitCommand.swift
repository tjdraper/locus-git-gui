/// The arguments to one `git` invocation, and whether it may change the repository.
nonisolated struct GitCommand: Sendable, Equatable {
    let arguments: [String]
    let isReadOnly: Bool

    static func reading(_ arguments: [String]) -> GitCommand {
        GitCommand(arguments: arguments, isReadOnly: true)
    }

    static func changing(_ arguments: [String]) -> GitCommand {
        GitCommand(arguments: arguments, isReadOnly: false)
    }
}
