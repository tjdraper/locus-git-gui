import Foundation
import Testing

struct ConflictMarkersTests {
    @Test
    func aConflictHasEachSideAndItsLabels() throws {
        // Arrange
        let text = "one\n<<<<<<< HEAD\nours\n=======\ntheirs\nmore\n>>>>>>> feature\ntwo\n"

        // Act
        let markers = ConflictMarkers(parsing: text)

        // Assert
        let conflict = try #require(markers.conflicts.first)
        let nsText = text as NSString
        #expect(markers.conflicts.count == 1)
        #expect(nsText.substring(with: conflict.range) == "<<<<<<< HEAD\nours\n=======\ntheirs\nmore\n>>>>>>> feature\n")
        #expect(nsText.substring(with: conflict.ours) == "ours\n")
        #expect(nsText.substring(with: conflict.theirs) == "theirs\nmore\n")
        #expect(conflict.base == nil)
        #expect(conflict.oursLabel == "HEAD")
        #expect(conflict.theirsLabel == "feature")
    }

    @Test
    func theAncestorIsReadWhenGitWroteIt() throws {
        // Arrange
        let text = "<<<<<<< ours\na\n||||||| base\nb\n=======\nc\n>>>>>>> theirs"

        // Act
        let conflict = try #require(ConflictMarkers(parsing: text).conflicts.first)

        // Assert
        let nsText = text as NSString
        #expect(nsText.substring(with: conflict.ours) == "a\n")
        #expect(nsText.substring(with: try #require(conflict.base)) == "b\n")
        #expect(nsText.substring(with: conflict.theirs) == "c\n")
        #expect(NSMaxRange(conflict.range) == nsText.length)
    }

    @Test
    func windowsLineEndingsStayInTheSides() throws {
        // Arrange
        let text = "<<<<<<< HEAD\r\nours\r\n=======\r\ntheirs\r\n>>>>>>> feature\r\n"

        // Act
        let conflict = try #require(ConflictMarkers(parsing: text).conflicts.first)

        // Assert
        let nsText = text as NSString
        #expect(nsText.substring(with: conflict.ours) == "ours\r\n")
        #expect(nsText.substring(with: conflict.theirs) == "theirs\r\n")
        #expect(conflict.theirsLabel == "feature")
    }

    @Test
    func aLongerMarkerOnlyCountsWithItsAttribute() {
        // Arrange
        let text = "<<<<<<<<< HEAD\na\n=========\nb\n>>>>>>>>> feature\n"

        // Act
        let atDefault = ConflictMarkers(parsing: text)
        let atNine = ConflictMarkers(parsing: text, markerSize: 9)

        // Assert
        #expect(atDefault.conflicts.isEmpty)
        #expect(atNine.conflicts.count == 1)
    }

    @Test
    func linesThatOnlyLookLikeMarkersAreText() {
        // Arrange
        let text = "Heading\n=======\n<<<<<<< HEAD\nno end\n=======\nstill none\n"

        // Act
        let markers = ConflictMarkers(parsing: text)

        // Assert
        #expect(markers.conflicts.isEmpty)
    }

    @Test
    func rangesCountAsATextViewDoes() throws {
        // Arrange
        let text = "👋🏽 café\n<<<<<<< HEAD\né\n=======\ne\n>>>>>>> feature\n"

        // Act
        let conflict = try #require(ConflictMarkers(parsing: text).conflicts.first)

        // Assert
        #expect((text as NSString).substring(with: conflict.ours) == "é\n")
        #expect(conflict.range.location == ("👋🏽 café\n" as NSString).length)
    }

    @Test
    func takingASideReplacesTheWholeConflict() throws {
        // Arrange
        let text = "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> feature\n" as NSString
        let conflict = try #require(ConflictMarkers(parsing: text as String).conflicts.first)

        // Act
        let ours = ConflictMarkers.resolution(of: conflict, in: text, choosing: .ours)
        let theirs = ConflictMarkers.resolution(of: conflict, in: text, choosing: .theirs)
        let both = ConflictMarkers.resolution(of: conflict, in: text, choosing: .oursThenTheirs)

        // Assert
        #expect(ours == "a\n")
        #expect(theirs == "b\n")
        #expect(both == "a\nb\n")
    }

    @Test
    func whatGitWritesInEachStyleIsRead() async throws {
        for style in ["merge", "diff3", "zdiff3"] {
            // Arrange
            let repository = try await FixtureRepository.mergeStoppedOnConflict(
                base: "1\n2\n3\n4\n5\n6\n7\n8\n9\n",
                main: "1\nmain\n3\n4\n5\n6\n7\nmain\n9\n",
                feature: "1\nfeature\n3\n4\n5\n6\n7\nfeature\n9\n",
                mergeOptions: ["-c", "merge.conflictStyle=\(style)"]
            )
            defer { repository.remove() }
            let text = try repository.contents(of: "notes.txt")

            // Act
            let markers = ConflictMarkers(parsing: text)

            // Assert
            let nsText = text as NSString
            #expect(markers.conflicts.count == 2)
            #expect(markers.conflicts.map { nsText.substring(with: $0.ours) } == ["main\n", "main\n"])
            #expect(markers.conflicts.map { nsText.substring(with: $0.theirs) } == ["feature\n", "feature\n"])
            #expect(markers.conflicts.map(\.theirsLabel) == ["feature", "feature"])
            #expect(markers.conflicts.allSatisfy { ($0.base != nil) == (style != "merge") })
        }
    }
}
