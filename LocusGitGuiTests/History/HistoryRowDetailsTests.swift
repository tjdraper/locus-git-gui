import Foundation
import Testing

struct HistoryRowDetailsTests {
    /// One point per character, so widths can be counted by eye.
    private func fit(labels: [CGFloat] = [], width: CGFloat) -> HistoryRowDetails {
        HistoryRowDetails.fit(
            HistoryRowDetails.Labels(widths: labels, spacing: 1) { _ in 3 },
            HistoryRowDetails.Parts(author: "Ada Lovelace", date: "2 days ago", hash: "1a2b3c4"),
            width: width
        ) { CGFloat($0.count) }
    }

    @Test
    func everythingShowsWhenThereIsRoom() {
        // Act
        let fit = fit(labels: [4, 6], width: 100)

        // Assert
        #expect(fit.labelCount == 2)
        #expect(fit.hiddenLabelCount == 0)
        #expect(fit.text == " · Ada Lovelace · 2 days ago · 1a2b3c4")
        #expect(!fit.isTruncated)
    }

    @Test
    func withoutLabelsTheTextHasNoLeadingSeparator() {
        // Act
        let fit = fit(width: 100)

        // Assert
        #expect(fit.text == "Ada Lovelace · 2 days ago · 1a2b3c4")
    }

    @Test
    func theHashGoesFirstThenTheDate() {
        // Act
        let withoutHash = fit(width: 30)
        let withoutDate = fit(width: 20)

        // Assert
        #expect(withoutHash.text == "Ada Lovelace · 2 days ago")
        #expect(withoutDate.text == "Ada Lovelace")
    }

    @Test
    func theAuthorIsCutOnlyWhenItAloneDoesNotFit() {
        // Act
        let cut = fit(width: 8)
        let none = fit(width: 2)

        // Assert
        #expect(cut.text == "Ada Lovelace")
        #expect(cut.isTruncated)
        #expect(none.text == nil)
    }

    @Test
    func labelsThatDoNotFitAreCountedInOneMoreLabel() {
        // Act
        let fit = fit(labels: [10, 10, 10], width: 25)

        // Assert
        #expect(fit.labelCount == 2)
        #expect(fit.hiddenLabelCount == 1)
    }

    @Test
    func labelsKeepTheirRoomBeforeTheAuthorDoes() {
        // Act
        let fit = fit(labels: [10, 10], width: 21)

        // Assert
        #expect(fit.labelCount == 2)
        #expect(fit.text == nil)
    }
}
