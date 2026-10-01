import Foundation
import Testing

/// Follows a review in a fixture repository the way a refresh does.
extension FixtureRepository {
    func refs() async throws -> [Ref] {
        try await Ref.parseList(run(Ref.listCommand).standardOutput)
    }

    func follow(_ review: Review, at date: Date = Date()) async throws -> (review: Review, listing: ReviewDiff.Listing) {
        let head = try await git("rev-parse", "HEAD")
        var review = try await ReviewFollowing.recordingRevision(
            of: review,
            refs: refs(),
            head: head,
            at: date
        ) { try await run($0) }
        let revision = try #require(review.revision)
        let listing = try await ReviewDiff.readFiles(
            from: revision.comparedBase,
            to: revision.comparedHead,
            workTree: folder
        ) { try await run($0) }
        review = ReviewFollowing.following(listing.files, in: review, at: date)
        return (review, listing)
    }
}
