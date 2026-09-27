/// What Fetch adds to `git fetch`: removing remote branches deleted on the remote, and fetching
/// every tag rather than only those on the branches fetched.
nonisolated struct FetchOptions: Equatable, Sendable {
    static let prune = FetchOptions(prunes: true)
    static let tags = FetchOptions(fetchesTags: true)

    var prunes = false
    var fetchesTags = false

    var arguments: [String] {
        (prunes ? ["--prune"] : []) + (fetchesTags ? ["--tags"] : [])
    }

    /// Fetch's title in the menu bar, saying what the options make it do, such as “Fetch (Prune, Tags)”.
    var fetchTitle: String {
        let notes = (prunes ? ["Prune"] : []) + (fetchesTags ? ["Tags"] : [])
        return notes.isEmpty ? AppCommand.fetch.title : "\(AppCommand.fetch.title) (\(notes.joined(separator: ", ")))"
    }
}
