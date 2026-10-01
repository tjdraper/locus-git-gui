import Foundation
import Testing

struct ReviewMarkdownTests {
    private func thread(_ place: ReviewThread.Place, _ bodies: [String], resolved: Bool = false) -> ReviewThread {
        ReviewThread(
            id: UUID(),
            place: place,
            comments: bodies.map { ReviewComment(id: UUID(), body: $0, created: Date()) },
            resolved: resolved ? Date() : nil
        )
    }

    private func anchor(_ path: String, _ lines: ClosedRange<Int>, _ text: [String]) -> ReviewLineAnchor {
        ReviewLineAnchor(path: path, side: .new, lines: lines, object: "abc", text: text, base: nil, head: nil)
    }

    @Test
    func unresolvedThreadsAreListedByFileAndLine() {
        // Arrange
        var review = Review(base: .ref("refs/heads/main"), head: .ref("refs/heads/feature"), created: Date())
        review.threads = [
            thread(.lines(anchor("b.swift", 9 ... 10, ["let x = 1", "let y = 2"])), ["Rename these.", "Done."]),
            thread(.file(path: "b.swift"), ["Needs tests."]),
            thread(.review, ["Looks close."]),
            thread(.lines(anchor("a.swift", 3 ... 3, ["call()"])), ["Resolved already."], resolved: true),
        ]

        // Act
        let markdown = ReviewMarkdown.unresolvedComments(of: review)

        // Assert
        #expect(markdown == """
        # feature → main

        ## The Review

        Looks close.

        ## `b.swift`

        Needs tests.

        **Lines 9–10**

        ```
        let x = 1
        let y = 2
        ```

        Rename these.

        **Reply:** Done.

        """)
    }
}
