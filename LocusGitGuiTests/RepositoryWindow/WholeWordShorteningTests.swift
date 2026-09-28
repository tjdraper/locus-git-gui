import Foundation
import Testing

struct WholeWordShorteningTests {
    @Test
    func dropsBracketsThenSentencesThenWords() {
        // Act
        let candidates = WholeWordShortening.candidates(for: "Reset “main” to 466c53a. It was at a25a934 (“Step 3”).")

        // Assert
        #expect(candidates == [
            "Reset “main” to 466c53a. It was at a25a934 (“Step 3”).",
            "Reset “main” to 466c53a. It was at a25a934.",
            "Reset “main” to 466c53a.",
            "Reset “main” to …",
            "Reset “main” …",
            "Reset …",
        ])
    }

    @Test
    func neverCutsAWordShort() {
        // Act
        let candidates = WholeWordShortening.candidates(for: "Deleted “feature”, which was at 1a2b3c4.")

        // Assert
        let words = Set("Deleted “feature”, which was at 1a2b3c4.".split(separator: " ").map(String.init) + ["…"])
        #expect(candidates.allSatisfy { $0.split(separator: " ").allSatisfy { words.contains(String($0)) } })
    }
}
