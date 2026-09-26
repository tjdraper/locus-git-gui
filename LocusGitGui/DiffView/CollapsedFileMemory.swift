/// Which files are collapsed in each diff a repository has shown, so a commit's changes, or the
/// working area's, come back as they were left. Only the most recently changed diffs are kept,
/// since every commit looked at could otherwise add one to the repository's saved view state.
nonisolated struct CollapsedFileMemory: Codable, Equatable, Sendable {
    enum Diff: Codable, Hashable, Sendable {
        case commit(String)
        case workingArea
    }

    private struct Entry: Codable, Equatable, Sendable {
        let diff: Diff
        let files: Set<DiffFile.Identity>
    }

    static let limit = 1000

    /// Oldest first.
    private var entries: [Entry] = []

    func files(in diff: Diff) -> Set<DiffFile.Identity> {
        entries.last { $0.diff == diff }?.files ?? []
    }

    /// A diff with nothing collapsed is forgotten, since that's how every diff starts.
    mutating func set(_ files: Set<DiffFile.Identity>, in diff: Diff) {
        entries.removeAll { $0.diff == diff }
        guard !files.isEmpty else { return }
        entries.append(Entry(diff: diff, files: files))
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
    }
}
