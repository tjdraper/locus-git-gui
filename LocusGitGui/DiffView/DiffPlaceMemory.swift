/// Where each diff a repository has shown was left, so a commit's changes, or the working area's,
/// come back as they were. Only the most recently changed diffs are kept, since every commit looked
/// at could otherwise add one to the repository's saved view state.
nonisolated struct DiffPlaceMemory: Codable, Equatable, Sendable {
    enum Diff: Codable, Hashable, Sendable {
        case commit(String)
        case workingArea
    }

    private struct Entry: Codable, Equatable, Sendable {
        let diff: Diff
        let place: DiffPlace
    }

    static let limit = 1000

    /// Oldest first.
    private var entries: [Entry] = []

    func place(in diff: Diff) -> DiffPlace {
        entries.last { $0.diff == diff }?.place ?? DiffPlace()
    }

    /// A diff left as every diff starts is forgotten.
    mutating func set(_ place: DiffPlace, in diff: Diff) {
        entries.removeAll { $0.diff == diff }
        guard place != DiffPlace() else { return }
        entries.append(Entry(diff: diff, place: place))
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
    }
}
