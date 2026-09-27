/// The Git commands that make and delete tags in this repository. Slice 10's `RemoteCommand` pushes
/// them to a remote and deletes them there.
nonisolated enum TagCommand {
    /// Annotated when it has a message, and lightweight when it doesn't.
    static func create(_ name: String, at commit: String, message: String) -> GitCommand {
        let annotation = message.isEmpty ? [] : ["--annotate", "--message", message]
        return .changing(["tag"] + annotation + ["--", name, commit])
    }

    static func delete(_ name: String) -> GitCommand {
        .changing(["tag", "--delete", "--", name])
    }
}
