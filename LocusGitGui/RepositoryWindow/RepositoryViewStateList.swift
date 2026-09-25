import Foundation

/// Every repository's view state, most recently changed first. It outlives the windows, so a
/// repository reopened next week comes back as it was left.
nonisolated struct RepositoryViewStateList: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// The repository's `id`.
        let repository: String
        var state: RepositoryViewState
    }

    /// As many as the recent list keeps.
    static let maxEntries = 1000

    private(set) var entries: [Entry] = []

    func state(for repository: String) -> RepositoryViewState {
        entries.first { $0.repository == repository }?.state ?? RepositoryViewState()
    }

    mutating func set(_ state: RepositoryViewState, for repository: String) {
        entries.removeAll { $0.repository == repository }
        entries.insert(Entry(repository: repository, state: state), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }
}

extension RepositoryViewStateList {
    private static let defaultsKey = "RepositoryViewStates"

    /// Kept on this Mac only, since the repositories on it and where they are differ from other Macs'.
    init(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let list = try? JSONDecoder().decode(RepositoryViewStateList.self, from: data)
        else {
            return
        }
        self = list
    }

    func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
