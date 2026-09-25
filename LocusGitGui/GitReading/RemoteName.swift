import Foundation

/// The names of the repository's remotes, from `git remote`. A remote shows even before anything
/// has been fetched from it, when it has no remote branches yet.
nonisolated enum RemoteName {
    static let listCommand = GitCommand.reading(["remote"])

    /// One name per line. A remote's name can't contain a newline.
    static func parseList(_ output: Data) throws -> [String] {
        try output.split(separator: UInt8(ascii: "\n")).map(UnreadableGitOutput.text)
    }
}
