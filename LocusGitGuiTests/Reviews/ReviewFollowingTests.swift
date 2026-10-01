import Foundation
import Testing

struct ReviewFollowingTests {
    /// `main` with one file, and `feature` branched from it changing that file and adding another.
    private func makeFeatureBranch() async throws -> FixtureRepository {
        let repository = try await FixtureRepository.make()
        try await repository.commit("Start", writing: "one\n", to: "a.txt")
        try await repository.git("checkout", "--quiet", "-b", "feature")
        try await repository.commit("Change a", writing: "one\ntwo\n", to: "a.txt")
        try await repository.commit("Add b", writing: "bee\n", to: "b.txt")
        return repository
    }

    private func featureReview() -> Review {
        Review(base: .ref("refs/heads/main"), head: .ref("refs/heads/feature"), created: Date())
    }

    @Test
    func aBranchIsComparedFromWhereItSplitFromTheBase() async throws {
        // Arrange
        let repository = try await makeFeatureBranch()
        defer { repository.remove() }
        try await repository.git("checkout", "--quiet", "main")
        try await repository.commit("Later on main", writing: "main only\n", to: "c.txt")
        try await repository.git("checkout", "--quiet", "feature")

        // Act
        let (review, listing) = try await repository.follow(featureReview())

        // Assert
        #expect(listing.files.map(\.path) == ["a.txt", "b.txt"])
        #expect(review.revisions.count == 1)
        #expect(review.revision?.mergeBase != review.revision?.base)
        #expect(review.progress == Review.Progress(files: 2))
    }

    @Test
    func aPointThatHasntMovedRecordsNoNewRevision() async throws {
        // Arrange
        let repository = try await makeFeatureBranch()
        defer { repository.remove() }
        let (first, _) = try await repository.follow(featureReview())

        // Act
        let (second, _) = try await repository.follow(first)

        // Assert
        #expect(second.revisions.count == 1)
    }

    @Test
    func aNewCommitClearsTheCheckOfOnlyTheFileItChanged() async throws {
        // Arrange
        let repository = try await makeFeatureBranch()
        defer { repository.remove() }
        var (review, listing) = try await repository.follow(featureReview())
        for file in listing.files {
            review.checks.check(ReviewedFile(file), at: Date())
        }
        review = ReviewFollowing.following(listing.files, in: review, at: Date())
        #expect(review.progress.isDone)

        // Act
        try await repository.commit("Change b", writing: "bee\nsting\n", to: "b.txt")
        (review, listing) = try await repository.follow(review)

        // Assert
        let fileA = try #require(listing.files.first { $0.path == "a.txt" })
        let fileB = try #require(listing.files.first { $0.path == "b.txt" })
        #expect(review.revisions.count == 2)
        #expect(review.checks.state(of: ReviewedFile(fileA)) == .checked)
        #expect(review.checks.state(of: ReviewedFile(fileB)) == .changedSinceReviewed)
        #expect(review.progress == Review.Progress(files: 2, checked: 1, changedSinceReviewed: 1))
    }

    @Test
    func aRebaseThatLeavesAFileAloneKeepsItsCheck() async throws {
        // Arrange
        let repository = try await makeFeatureBranch()
        defer { repository.remove() }
        var (review, listing) = try await repository.follow(featureReview())
        for file in listing.files {
            review.checks.check(ReviewedFile(file), at: Date())
        }
        try await repository.git("checkout", "--quiet", "main")
        try await repository.commit("Unrelated", writing: "see\n", to: "c.txt")
        try await repository.git("checkout", "--quiet", "feature")

        // Act
        try await repository.git("rebase", "--quiet", "main")
        (review, listing) = try await repository.follow(review)

        // Assert
        #expect(review.revisions.count == 2)
        #expect(listing.files.map(\.path) == ["a.txt", "b.txt"])
        #expect(review.progress.isDone)
    }

    @Test
    func aDeletedBranchLeavesTheReviewWhereItWas() async throws {
        // Arrange
        let repository = try await makeFeatureBranch()
        defer { repository.remove() }
        let (first, _) = try await repository.follow(featureReview())
        try await repository.git("checkout", "--quiet", "main")

        // Act
        try await repository.git("branch", "--quiet", "-D", "feature")
        let (review, listing) = try await repository.follow(first)

        // Assert
        #expect(review.missingPoints == [.ref("refs/heads/feature")])
        #expect(review.revisions == first.revisions)
        #expect(listing.files.map(\.path) == ["a.txt", "b.txt"])
    }

    @Test
    func theWorkingTreeIncludesStagedUnstagedAndUntrackedFiles() async throws {
        // Arrange
        let repository = try await makeFeatureBranch()
        defer { repository.remove() }
        try repository.write("one\ntwo\nthree\n", to: "a.txt")
        try repository.write("staged\n", to: "s.txt")
        try await repository.git("add", "s.txt")
        try repository.write("new\n", to: "new/u.txt")
        let review = Review(base: .checkedOut, head: .workingTree, created: Date())

        // Act
        let (followed, listing) = try await repository.follow(review)

        // Assert
        #expect(listing.files.map(\.path) == ["a.txt", "new/u.txt", "s.txt"])
        #expect(listing.untracked == ["new/u.txt"])
        #expect(listing.files.allSatisfy { $0.newObject != nil })
        let expected = try await repository.git("hash-object", "a.txt")
        #expect(listing.files.first?.newObject == expected)
        #expect(followed.revision?.includesWorkingTree == true)
    }

    @Test
    func editingAWorkingTreeFileClearsItsCheck() async throws {
        // Arrange
        let repository = try await makeFeatureBranch()
        defer { repository.remove() }
        try repository.write("one\ntwo\nthree\n", to: "a.txt")
        var (review, listing) = try await repository.follow(
            Review(base: .checkedOut, head: .workingTree, created: Date())
        )
        review.checks.check(ReviewedFile(listing.files[0]), at: Date())

        // Act
        try repository.write("one\ntwo\nthree\nfour\n", to: "a.txt")
        (review, listing) = try await repository.follow(review)

        // Assert
        #expect(review.checks.state(of: ReviewedFile(listing.files[0])) == .changedSinceReviewed)
        #expect(review.revisions.count == 1)
    }

    @Test
    func changesSinceReviewedCompareTheReviewedVersionWithTheCurrentOne() async throws {
        // Arrange
        let repository = try await makeFeatureBranch()
        defer { repository.remove() }
        var (review, listing) = try await repository.follow(featureReview())
        review.checks.check(ReviewedFile(listing.files[0]), at: Date())
        try await repository.commit("More a", writing: "one\ntwo\nthree\n", to: "a.txt")
        (review, listing) = try await repository.follow(review)
        let reviewed = try #require(review.checks.reviewedVersion(of: "a.txt")?.newObject)
        let current = try #require(listing.files[0].newObject)

        // Act
        let file = try await ReviewDiff.readChangesSince(
            (reviewed, current),
            in: listing.files[0],
            options: DiffOptions(),
            limits: .allFiles,
            readingPatch: repository.readPatch
        )

        // Assert
        let changed = file.patch.hunks.flatMap(\.lines).filter { $0.kind != .context }
        #expect(changed.map(\.text) == ["three"])
        #expect(changed.first?.newNumber == 3)
    }

    @Test
    func aFilesChangesReadForTheRevision() async throws {
        // Arrange
        let repository = try await makeFeatureBranch()
        defer { repository.remove() }
        let (review, listing) = try await repository.follow(featureReview())
        let revision = try #require(review.revision)

        // Act
        let file = try await ReviewDiff.readFile(
            listing.files[0],
            isUntracked: false,
            from: ReviewDiff.Source(revision: revision, options: DiffOptions(), workTree: repository.folder),
            limits: .allFiles,
            readingPatch: repository.readPatch
        )

        // Assert
        #expect(file.patch.added == 1)
        #expect(file.patch.hunks.flatMap(\.lines).last?.text == "two")
    }
}
