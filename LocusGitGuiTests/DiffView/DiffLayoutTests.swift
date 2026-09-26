import Foundation
import Testing

struct DiffLayoutTests {
    private let metrics = DiffLayout.Metrics(advance: 10, lineHeight: 20)

    private func files(_ lines: [String]) -> [DiffFile] {
        var parser = PatchParser(limits: .allFiles)
        let body = lines.map { "+" + $0 + "\n" }.joined()
        parser.consume(Data("diff --git a/a b/a\n@@ -0,0 +1,\(lines.count) @@\n\(body)".utf8))
        return [DiffFile(changed: ChangedFile(change: .added, path: "a", originalPath: nil), patch: parser.finish()[0])]
    }

    @Test
    func aLongLineIsAsTallAsTheLinesItWrapsTo() {
        // Arrange
        let files = files(["short", String(repeating: "word ", count: 40)])
        let document = DiffDocument(files: files, collapsed: [], style: .inline)

        // Act
        let layout = DiffLayout(document: document, files: files, metrics: metrics, width: 600, numberColumns: 3)

        // Assert
        let columns = layout.sides[0].textColumns
        let expectedLines = LineWrap.wrap(Array(String(repeating: "word ", count: 40).utf16), columns: columns).count
        #expect(expectedLines > 1)
        #expect(layout.frame(of: 2).maxY - layout.frame(of: 2).minY == metrics.lineHeight)
        #expect(layout.frame(of: 3).maxY - layout.frame(of: 3).minY == Double(expectedLines) * metrics.lineHeight)
        #expect(layout.height == metrics.headerHeight + metrics.hunkHeight + Double(1 + expectedLines) * metrics.lineHeight)
    }

    @Test
    func findsTheBlockAtAHeight() {
        // Arrange
        let files = files(["one", "two"])
        let document = DiffDocument(files: files, collapsed: [], style: .inline)
        let layout = DiffLayout(document: document, files: files, metrics: metrics, width: 600, numberColumns: 3)

        // Act & Assert
        #expect(layout.block(atY: 0) == 0)
        #expect(layout.block(atY: metrics.headerHeight) == 1)
        #expect(layout.block(atY: metrics.headerHeight + metrics.hunkHeight + metrics.lineHeight + 1) == 3)
        #expect(layout.block(atY: layout.height) == nil)
        #expect(layout.blocks(from: 0, to: metrics.headerHeight + 1) == 0 ..< 2)
    }

    @Test
    func goesSideBySideOnlyWhenBothSidesHaveRoom() {
        // Act
        let narrow = DiffLayout.style(forWidth: 1000, metrics: metrics, numberColumns: 3)
        let wide = DiffLayout.style(forWidth: 2000, metrics: metrics, numberColumns: 3)

        // Assert
        #expect(narrow == .inline)
        #expect(wide == .sideBySide)
    }
}
