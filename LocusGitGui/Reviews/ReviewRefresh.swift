import Foundation

/// Brings one review up to date with the repository as a refresh read it: a revision when a point
/// has moved, then its files, with the checks following them. Git runs between the steps, so each
/// is applied to the review as it is by then, and a check made meanwhile stays.
enum ReviewRefresh {
    /// Nil when the review is gone, or its points can't be found and it has never been read.
    /// `onlyWhenMoved` leaves the files of a review that compares two commits alone until one of
    /// them moves, since they can't have changed, for reviews no window shows.
    static func run(
        _ id: UUID,
        store: ReviewStore,
        refs: [Ref],
        head: String?,
        commands: RepositoryCommandRunner,
        onlyWhenMoved: Bool = false
    ) async throws -> (revision: ReviewRevision, listing: ReviewDiff.Listing)? {
        let repository = commands.repository
        guard let review = store.review(id, in: repository) else { return nil }
        let movement = try await ReviewFollowing.movement(of: review, refs: refs, head: head, at: Date(), running: commands.run)
        store.update(id, in: repository) { $0 = ReviewFollowing.applying(movement, to: $0) }
        guard let revision = store.review(id, in: repository)?.revision else { return nil }
        if onlyWhenMoved, movement.revision == nil, !revision.includesWorkingTree {
            return nil
        }
        let listing = try await ReviewDiff.readFiles(
            from: revision.comparedBase,
            to: revision.comparedHead,
            workTree: repository.workTree,
            running: commands.run
        )
        try Task.checkCancellation()
        store.update(id, in: repository) { review in
            guard review.revision?.place == revision.place else { return }
            review = ReviewFollowing.following(listing.files, in: review, at: Date())
        }
        return (revision, listing)
    }
}
