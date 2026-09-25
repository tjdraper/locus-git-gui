import Foundation

/// The recent list the app reads and changes, saved as soon as it changes.
@Observable
final class RecentRepositoryStore {
    private(set) var list: RecentRepositoryList {
        didSet { list.save(to: defaults) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        list = RecentRepositoryList(defaults: defaults)
    }

    var entries: [RecentRepository] {
        list.entries
    }

    func note(_ repository: Repository) {
        list.note(repository)
    }

    @discardableResult
    func remove(_ repositories: [Repository]) -> [RecentRepositoryList.Removal] {
        list.remove(repositories)
    }

    func restore(_ removed: [RecentRepositoryList.Removal]) {
        list.restore(removed)
    }

    func removeAll() {
        list.removeAll()
    }

    /// Only changes the list when the name did, since every change saves it.
    func setDisplayName(_ displayName: String?, for repository: Repository) {
        guard list.entries.first(where: { $0.id == repository.id })?.displayName != displayName else { return }
        list.setDisplayName(displayName, for: repository)
    }
}
