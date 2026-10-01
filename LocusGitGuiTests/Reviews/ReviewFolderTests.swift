import Foundation
import Testing

struct ReviewFolderTests {
    private func makeFolder() -> ReviewFolder {
        ReviewFolder(folder: FileManager.default.temporaryDirectory.appending(path: "Reviews-\(UUID().uuidString)"))
    }

    private func remove(_ folder: ReviewFolder) {
        try? FileManager.default.removeItem(at: folder.folder)
    }

    @Test
    func aSavedReviewReadsBackWhole() throws {
        // Arrange
        let folder = makeFolder()
        defer { remove(folder) }
        var review = Review(base: .ref("refs/heads/main"), head: .workingTree, created: Date())
        review.checks.check(ReviewedFile(path: "a", oldMode: "100644", newMode: "100644", oldObject: "1", newObject: "2"), at: Date())
        let anchor = ReviewLineAnchor(path: "a", side: .new, lines: 3...4, object: "2", text: ["x", "y"], base: "b", head: "h")
        review.threads = [
            ReviewThread(id: UUID(), place: .lines(anchor), comments: [ReviewComment(id: UUID(), body: "Why?", created: Date())]),
        ]
        review.missingPoints = [.commit("abc")]

        // Act
        try folder.write(review, for: "/work/website")

        // Assert
        #expect(folder.read("/work/website") == [review])
    }

    @Test
    func eachRepositoryKeepsItsOwnReviews() throws {
        // Arrange
        let folder = makeFolder()
        defer { remove(folder) }
        let website = Review(name: "website", base: .checkedOut, head: .workingTree, created: Date())
        let api = Review(name: "api", base: .checkedOut, head: .workingTree, created: Date())

        // Act
        try folder.write(website, for: "/work/website")
        try folder.write(api, for: "/work/api")

        // Assert
        #expect(folder.read("/work/website").map(\.name) == ["website"])
        #expect(folder.read("/work/api").map(\.name) == ["api"])
    }

    @Test
    func aDeletedReviewIsGone() throws {
        // Arrange
        let folder = makeFolder()
        defer { remove(folder) }
        let review = Review(name: "website", base: .checkedOut, head: .workingTree, created: Date())
        try folder.write(review, for: "/work/website")

        // Act
        try folder.delete(review.id, for: "/work/website")

        // Assert
        #expect(folder.read("/work/website").isEmpty)
    }
}
