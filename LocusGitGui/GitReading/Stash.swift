import Foundation

/// One entry from `git stash list`, newest first, so an entry's place in the list is the `n` in
/// `stash@{n}`.
nonisolated struct Stash: Equatable, Sendable {
    /// The placeholders in the order `parseList` reads them. `%gd` would name the entry, but a
    /// `--date` in the user's config turns it into `stash@{<date>}`, so the position stands in.
    private static let placeholders = ["%H", "%ct", "%gs"]

    static let listCommand = GitCommand.reading([
        "stash", "list", "-z", "--no-show-signature", "--format=" + placeholders.joined(separator: "%x00"),
    ])

    /// Stays the same while newer stashes push this one down the list.
    let commit: String
    let date: Date
    /// Git's own description, such as "WIP on main: 1a2b3c4 Subject" or "On main: a message".
    let message: String

    /// Laid out like `Commit.parseLog`: every field and every entry ends in a NUL.
    static func parseList(_ output: Data) throws -> [Stash] {
        var fields = try output.split(separator: 0, omittingEmptySubsequences: false).map(UnreadableGitOutput.text)
        if fields.last?.isEmpty == true {
            fields.removeLast()
        }
        guard fields.count.isMultiple(of: placeholders.count) else {
            throw UnreadableGitOutput(reason: "Stash list has \(fields.count) fields, not a multiple of \(placeholders.count)")
        }
        return try stride(from: 0, to: fields.count, by: placeholders.count).map { start in
            guard let seconds = TimeInterval(fields[start + 1]) else {
                throw UnreadableGitOutput(reason: "Malformed stash date")
            }
            return Stash(commit: fields[start], date: Date(timeIntervalSince1970: seconds), message: fields[start + 2])
        }
    }
}
