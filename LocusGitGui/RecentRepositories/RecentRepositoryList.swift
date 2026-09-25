import Foundation

/// A repository on the recent list, with the display name it had when last seen.
nonisolated struct RecentRepository: Equatable, Sendable, Identifiable {
    let repository: Repository
    /// Kept here so the menus can show it without reading every repository's `.locus` folder.
    var displayName: String?

    var id: String {
        repository.id
    }
}

/// Stored flat, alongside the repository's own fields, which also reads lists saved before
/// repositories had display names.
extension RecentRepository: Codable {
    private enum CodingKeys: String, CodingKey {
        case displayName
    }

    init(from decoder: any Decoder) throws {
        repository = try Repository(from: decoder)
        displayName = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .displayName)
    }

    func encode(to encoder: any Encoder) throws {
        try repository.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
    }
}

/// Every repository opened before, most recent first. The dashboard, File > Open Recent and the
/// Dock menu all show this one list.
nonisolated struct RecentRepositoryList: Equatable, Codable {
    /// Where something removed from the list was, so it can be put back.
    struct Removal: Equatable, Sendable {
        let index: Int
        let entry: RecentRepository
    }

    static let limit = 1000

    private(set) var entries: [RecentRepository] = []

    private enum CodingKeys: String, CodingKey {
        case entries = "repositories"
    }

    /// Opening a repository again keeps the display name it had.
    mutating func note(_ repository: Repository) {
        let displayName = entries.first { $0.id == repository.id }?.displayName
        remove([repository])
        entries.insert(RecentRepository(repository: repository, displayName: displayName), at: 0)
        trimToLimit()
    }

    @discardableResult
    mutating func remove(_ repositories: [Repository]) -> [Removal] {
        let ids = Set(repositories.map(\.id))
        let removed = entries.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { Removal(index: $0.offset, entry: $0.element) }
        entries.removeAll { ids.contains($0.id) }
        return removed
    }

    /// A repository opened again since it was removed stays where opening put it.
    mutating func restore(_ removed: [Removal]) {
        for removal in removed.sorted(by: { $0.index < $1.index }) where !entries.contains(where: { $0.id == removal.entry.id }) {
            entries.insert(removal.entry, at: min(removal.index, entries.count))
        }
        trimToLimit()
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    mutating func setDisplayName(_ displayName: String?, for repository: Repository) {
        guard let index = entries.firstIndex(where: { $0.id == repository.id }) else { return }
        entries[index].displayName = displayName
    }

    private mutating func trimToLimit() {
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
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
