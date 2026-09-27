import Foundation
import Testing

struct GitProgressTests {
    @Test
    func aPhaseWithATotalHasAFraction() {
        // Arrange
        let line = "Receiving objects:  49% (148/302), 2.84 MiB | 5.67 MiB/s"

        // Act
        let progress = GitProgress(line: line)

        // Assert
        #expect(progress == GitProgress(phase: "Receiving objects", completed: 148, total: 302))
        #expect(progress?.fraction == 148.0 / 302.0)
    }

    @Test
    func theServersPhasesLoseTheirRemotePrefix() {
        // Arrange
        let line = "remote: Counting objects:   8% (25/302)        "

        // Act
        let progress = GitProgress(line: line)

        // Assert
        #expect(progress == GitProgress(phase: "Counting objects", completed: 25, total: 302))
    }

    @Test
    func aPhaseThatOnlyCountsHasNoFraction() {
        // Arrange
        let line = "remote: Enumerating objects: 302, done."

        // Act
        let progress = GitProgress(line: line)

        // Assert
        #expect(progress == GitProgress(phase: "Enumerating objects", completed: 302, total: nil))
        #expect(progress?.fraction == nil)
    }

    @Test
    func otherLinesAreNotProgress() {
        // Arrange
        let lines = [
            "Cloning into 'dst'...",
            "remote: Pushes to main need a pull request.",
            " ! [rejected]        main -> main (fetch first)",
        ]

        // Act
        let progress = lines.map(GitProgress.init(line:))

        // Assert
        #expect(progress.allSatisfy { $0 == nil })
    }

    @Test
    func theReaderGivesTheLatestAcrossSplitChunks() {
        // Arrange
        var reader = GitProgress.Reader()
        let output = "Cloning into 'dst'...\nReceiving objects:   2% (7/302)\rReceiving objects:  49% (148/302)\rResolving del"

        // Act
        let first = reader.consume(Data(output.utf8))
        let second = reader.consume(Data("tas: 100% (4/4), done.\n".utf8))

        // Assert
        #expect(first == GitProgress(phase: "Receiving objects", completed: 148, total: 302))
        #expect(second == GitProgress(phase: "Resolving deltas", completed: 4, total: 4))
    }
}
