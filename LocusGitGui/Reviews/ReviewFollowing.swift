import Foundation

/// Keeps a review up to date with the repository: a new revision when a point it follows has
/// moved, and checks that follow the files as they are now.
nonisolated enum ReviewFollowing {
    /// Where a review's points have got to, worked out away from the review itself, so a check
    /// made while Git runs isn't lost when this is applied.
    struct Movement: Sendable {
        let base: ReviewPoint
        let head: ReviewPoint
        /// Nil when neither point has moved.
        let revision: ReviewRevision?
        let missingPoints: Set<ReviewPoint>
    }

    /// Records a revision when either point is somewhere new. A point that can't be found leaves
    /// the review where it last was.
    static func recordingRevision(
        of review: Review,
        refs: [Ref],
        head: String?,
        at date: Date,
        running run: ReviewDiff.Run
    ) async throws -> Review {
        try await applying(movement(of: review, refs: refs, head: head, at: date, running: run), to: review)
    }

    static func movement(
        of review: Review,
        refs: [Ref],
        head: String?,
        at date: Date,
        running run: ReviewDiff.Run
    ) async throws -> Movement {
        let base = review.base.resolve(in: refs, head: head)
        let headSide = review.head.resolve(in: refs, head: head)
        let missing = Set([(review.base, base), (review.head, headSide)].compactMap { point, resolution in
            resolution == .missing ? point : nil
        })
        guard let place = ReviewRevision.place(base: base, head: headSide), place != review.revision?.place else {
            return Movement(base: review.base, head: review.head, revision: nil, missingPoints: missing)
        }
        let mergeBase: String? = if place.base == place.head {
            nil
        } else {
            try ReviewRevision.parseMergeBase(await run(ReviewRevision.mergeBaseCommand(place)))
        }
        let revision = ReviewRevision(place, mergeBase: mergeBase, recorded: date)
        return Movement(base: review.base, head: review.head, revision: revision, missingPoints: missing)
    }

    /// Left alone when the review's points were changed since the movement was worked out.
    static func applying(_ movement: Movement, to review: Review) -> Review {
        guard movement.base == review.base, movement.head == review.head else { return review }
        var review = review
        review.missingPoints = movement.missingPoints
        if let revision = movement.revision, revision.place != review.revision?.place {
            review.revisions.append(revision)
            review.lastChanged = revision.recorded
        }
        return review
    }

    /// The checks and progress for the review's files as they are now.
    static func following(_ files: [ChangedFile], in review: Review, at date: Date) -> Review {
        var review = review
        let reviewed = files.map(ReviewedFile.init)
        if review.checks.follow(reviewed) {
            review.lastChanged = date
        }
        review.progress = progress(of: reviewed, in: review.checks)
        return review
    }

    static func progress(of files: [ReviewedFile], in checks: ReviewChecks) -> Review.Progress {
        var progress = Review.Progress(files: files.count)
        for file in files {
            switch checks.state(of: file) {
            case .checked: progress.checked += 1
            case .changedSinceReviewed: progress.changedSinceReviewed += 1
            case .unchecked: break
            }
        }
        return progress
    }
}
