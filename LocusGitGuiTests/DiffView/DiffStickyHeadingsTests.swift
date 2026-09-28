import Foundation
import Testing

struct DiffStickyHeadingsTests {
    private let metrics = DiffLayout.Metrics(advance: 10, lineHeight: 20)

    /// Two groups of two files each, all collapsed, so every block is a heading or a header.
    private func diff(headsGroups: Bool = true) -> (DiffDocument, DiffLayout) {
        let files = (0 ..< 4).map { index in
            DiffFile(changed: ChangedFile(change: .modified, path: "\(index).txt", originalPath: nil), patch: FilePatch(), group: index / 2)
        }
        let document = DiffDocument(files: files, collapsed: [0, 1, 2, 3], style: .inline, headsGroups: headsGroups)
        let layout = DiffLayout(document: document, files: files, metrics: metrics, width: 800, numberColumns: 3)
        return (document, layout)
    }

    @Test
    func knowsEachFilesGroupHeadingAndWhereTheGroupEnds() {
        // Act
        let (document, _) = diff()

        // Assert
        #expect(document.fileGroupHeadings == [0, 0, 3, 3])
        #expect(document.groupEnds == [0: 3, 3: 6])
    }

    @Test
    func holdsTheHeadingAtTheTopWhileItsGroupScrollsPast() {
        // Arrange
        let (document, layout) = diff()

        // Act
        let heading = DiffStickyHeadings.heading(atTop: 10, document: document, layout: layout)

        // Assert
        #expect(heading == DiffStickyHeadings.Heading(block: 0, y: 10))
        #expect(DiffStickyHeadings.cover(atTop: 10, document: document, layout: layout) == metrics.groupHeight)
    }

    @Test
    func theNextGroupPushesTheHeadingUpWithTheHeaderBelowIt() {
        // Arrange
        let (document, layout) = diff()
        let groupEnd = layout.top(of: 3)
        let top = groupEnd - metrics.groupHeight - metrics.headerHeight + 14

        // Act
        let heading = DiffStickyHeadings.heading(atTop: top, document: document, layout: layout)

        // Assert
        #expect(heading?.y == top - 14)
        #expect(DiffStickyHeadings.cover(atTop: top, document: document, layout: layout) == metrics.groupHeight - 14)
    }

    @Test
    func theNextGroupsHeadingTakesOverOnceItReachesTheTop() {
        // Arrange
        let (document, layout) = diff()

        // Act
        let heading = DiffStickyHeadings.heading(atTop: layout.top(of: 3) + 5, document: document, layout: layout)

        // Assert
        #expect(heading?.block == 3)
    }

    @Test
    func aDiffWithoutGroupHeadingsHoldsNothing() {
        // Arrange
        let (document, layout) = diff(headsGroups: false)

        // Act
        let heading = DiffStickyHeadings.heading(atTop: 10, document: document, layout: layout)

        // Assert
        #expect(heading == nil)
        #expect(DiffStickyHeadings.offset(ofFile: 1, document: document, layout: layout) == 0)
    }
}
