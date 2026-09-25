import Foundation

/// Every repository opened before, most recent first. The dashboard, File > Open Recent and the
/// Dock menu all show this one list.
nonisolated struct RecentRepositoryList: Equatable, Codable {
    /// The dashboard checks every repository on the list each time it opens, which runs Git in each.
    static let limit = 100

    private(set) var repositories: [Repository] = []

    mutating func note(_ repository: Repository) {
        remove(repository)
        repositories.insert(repository, at: 0)
        if repositories.count > Self.limit {
            repositories.removeLast(repositories.count - Self.limit)
        }
    }

    mutating func remove(_ repository: Repository) {
        repositories.removeAll { $0.id == repository.id }
    }

    mutating func removeAll() {
        repositories.removeAll()
    }
}

extension RecentRepositoryList {
    private static let defaultsKey = "RecentRepositories"

    /// An unreadable list starts over empty rather than stopping the app from launching.
    init(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let list = try? JSONDecoder().decode(RecentRepositoryList.self, from: data)
        else {
            return
        }
        self = list
    }

    func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
