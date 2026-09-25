import Foundation

/// The view state of every repository, saved a moment after it stops changing. Dragging a column
/// divider changes it many times a second, and each save writes the whole list.
final class RepositoryViewStateStore {
    private static let saveDelay: Duration = .seconds(1)

    private var list: RepositoryViewStateList
    private let defaults: UserDefaults
    private var pendingSave: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        list = RepositoryViewStateList(defaults: defaults)
    }

    func state(for repository: Repository) -> RepositoryViewState {
        list.state(for: repository.id)
    }

    func set(_ state: RepositoryViewState, for repository: Repository) {
        guard state != list.state(for: repository.id) else { return }
        list.set(state, for: repository.id)
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Called at quit, when a save still waiting would be lost.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        list.save(to: defaults)
    }
}
