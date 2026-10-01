import Foundation

/// Every repository's reviews, read from their files when the repository's window opens, and
/// written a moment after each stops changing, off the main actor. One for the app, as there's one
/// folder of reviews.
@Observable
final class ReviewStore {
    static let shared = ReviewStore()

    private static let saveDelay: Duration = .seconds(1)

    private struct Change {
        let key: ReviewWriter.Key
        let review: Review
        /// Counts up with each change handed over, so the writer can tell which is newest.
        let version: Int
    }

    @ObservationIgnored private let folder: ReviewFolder
    @ObservationIgnored private let writer: ReviewWriter
    /// By repository, then by review.
    private var reviews: [String: [UUID: Review]] = [:]
    @ObservationIgnored private var changed: Set<ReviewWriter.Key> = []
    @ObservationIgnored private var versions: [ReviewWriter.Key: Int] = [:]
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init(folder: ReviewFolder = ReviewFolder(folder: ReviewFolder.defaultFolder)) {
        self.folder = folder
        writer = ReviewWriter(folder: folder)
    }

    /// Before anything else asks for the repository's reviews, and outside a view's update, since
    /// reading them changes what views observe.
    func load(_ repository: Repository) {
        guard reviews[repository.id] == nil else { return }
        reviews[repository.id] = Dictionary(folder.read(repository.id).map { ($0.id, $0) }) { first, _ in first }
    }

    func reviews(in repository: Repository) -> [Review] {
        Array(reviews[repository.id, default: [:]].values)
    }

    func review(_ id: UUID, in repository: Repository) -> Review? {
        reviews[repository.id]?[id]
    }

    func add(_ review: Review, in repository: Repository) {
        load(repository)
        reviews[repository.id, default: [:]][review.id] = review
        save(review.id, in: repository)
    }

    /// Nothing happens for a review that's been deleted, which a read that finishes late can try.
    func update(_ id: UUID, in repository: Repository, _ change: (inout Review) -> Void) {
        guard var review = reviews[repository.id]?[id] else { return }
        change(&review)
        guard review != reviews[repository.id]?[id] else { return }
        reviews[repository.id]?[id] = review
        save(id, in: repository)
    }

    func delete(_ id: UUID, in repository: Repository) {
        reviews[repository.id]?[id] = nil
        let key = ReviewWriter.Key(repository: repository.id, review: id)
        changed.remove(key)
        Task { [writer] in await writer.delete(key) }
    }

    /// As the app quits: returns once every change has been written.
    func finish() async {
        pendingSave?.cancel()
        await write(takeChanges())
        await writer.finish()
    }

    private func save(_ id: UUID, in repository: Repository) {
        changed.insert(ReviewWriter.Key(repository: repository.id, review: id))
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            await write(takeChanges())
        }
    }

    private func takeChanges() -> [Change] {
        pendingSave = nil
        let changes = changed.compactMap { key -> Change? in
            guard let review = reviews[key.repository]?[key.review] else { return nil }
            let version = (versions[key] ?? 0) + 1
            versions[key] = version
            return Change(key: key, review: review, version: version)
        }
        changed = []
        return changes
    }

    private func write(_ changes: [Change]) async {
        for change in changes {
            await writer.write(change.review, for: change.key, version: change.version)
        }
    }
}
