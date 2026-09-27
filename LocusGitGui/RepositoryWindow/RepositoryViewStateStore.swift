import Foundation

/// The view state of every repository, read from its file when its window opens and written a
/// moment after it stops changing, off the main actor. Scrolling and dragging a column divider
/// change it many times a second.
final class RepositoryViewStateStore {
    private static let saveDelay: Duration = .seconds(1)

    private struct Change {
        let repository: String
        let state: RepositoryViewState
        /// Counts up with each change handed over, so the writer can tell which is newest.
        let version: Int
    }

    private let files: RepositoryViewStateFiles
    private let writer: RepositoryViewStateWriter
    private var states: [String: RepositoryViewState] = [:]
    private var versions: [String: Int] = [:]
    private var changed: Set<String> = []
    private var pendingSave: Task<Void, Never>?

    init(files: RepositoryViewStateFiles = RepositoryViewStateFiles(folder: RepositoryViewStateFiles.defaultFolder)) {
        self.files = files
        writer = RepositoryViewStateWriter(files: files)
        Task { [writer] in await writer.prune() }
    }

    func state(for repository: Repository) -> RepositoryViewState {
        if let state = states[repository.id] {
            return state
        }
        let state = files.read(repository.id) ?? RepositoryViewState()
        states[repository.id] = state
        return state
    }

    func set(_ state: RepositoryViewState, for repository: Repository) {
        guard state != states[repository.id] else { return }
        states[repository.id] = state
        changed.insert(repository.id)
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            await write(takeChanges())
        }
    }

    /// As the app quits: returns once every change has been written.
    func finish() async {
        pendingSave?.cancel()
        await write(takeChanges())
        await writer.finish()
    }

    private func takeChanges() -> [Change] {
        pendingSave = nil
        let changes = changed.compactMap { repository -> Change? in
            guard let state = states[repository] else { return nil }
            let version = (versions[repository] ?? 0) + 1
            versions[repository] = version
            return Change(repository: repository, state: state, version: version)
        }
        changed = []
        return changes
    }

    private func write(_ changes: [Change]) async {
        for change in changes {
            await writer.write(change.state, for: change.repository, version: change.version)
        }
    }
}
