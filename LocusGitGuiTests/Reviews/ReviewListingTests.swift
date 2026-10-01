import Foundation
import Testing

struct ReviewListingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func review(_ name: String, openedDaysAgo opened: Int, changedDaysAgo changed: Int) -> Review {
        var review = Review(name: name, base: .checkedOut, head: .workingTree, created: now.addingTimeInterval(-200 * 86400))
        review.lastOpened = now.addingTimeInterval(Double(-opened) * 86400)
        review.lastChanged = now.addingTimeInterval(Double(-changed) * 86400)
        return review
    }

    @Test
    func reviewsNotOpenedInNinetyDaysAreLeftOut() {
        // Arrange
        let reviews = [review("recent", openedDaysAgo: 89, changedDaysAgo: 100), review("old", openedDaysAgo: 91, changedDaysAgo: 91)]

        // Act
        let shown = ReviewListing.shown(reviews, at: now, includingOlder: false)

        // Assert
        #expect(shown.map(\.name) == ["recent"])
        #expect(ReviewListing.olderCount(reviews, at: now) == 1)
    }

    @Test
    func theMostRecentlyChangedComeFirst() {
        // Arrange
        let reviews = [
            review("a", openedDaysAgo: 1, changedDaysAgo: 5),
            review("b", openedDaysAgo: 5, changedDaysAgo: 1),
            review("c", openedDaysAgo: 120, changedDaysAgo: 3),
        ]

        // Act
        let shown = ReviewListing.shown(reviews, at: now, includingOlder: true)

        // Assert
        #expect(shown.map(\.name) == ["b", "c", "a"])
    }
}
