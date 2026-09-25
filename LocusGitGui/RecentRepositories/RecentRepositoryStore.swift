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

    var repositories: [Repository] {
        list.repositories
    }

    func note(_ repository: Repository) {
        list.note(repository)
    }

    func remove(_ repository: Repository) {
        list.remove(repository)
    }

    func removeAll() {
        list.removeAll()
    }
}
