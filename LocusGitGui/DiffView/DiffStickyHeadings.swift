import Foundation

/// Where a grouped diff's group heading is held at the top of the view while its files scroll past,
/// with the file headers held just below it, so a group's Stage All is in reach wherever the view is.
/// A heading is pushed up by the group after it, along with the header below it.
nonisolated enum DiffStickyHeadings {
    struct Heading: Equatable, Sendable {
        /// Its index in the document's blocks.
        let block: Int
        let y: Double
    }

    /// The heading of the group at the top of the view, where it's drawn. Nil in a diff without
    /// group headings.
    static func heading(atTop top: Double, document: DiffDocument, layout: DiffLayout) -> Heading? {
        guard let atTop = layout.block(atY: max(top, 0)), let file = document.file(at: atTop),
              let block = document.fileGroupHeadings[file], let end = document.groupEnds[block]
        else { return nil }
        let metrics = layout.metrics
        let pushedUp = layout.top(of: end) - metrics.groupHeight - metrics.headerHeight
        return Heading(block: block, y: min(max(top, layout.top(of: block)), max(pushedUp, layout.top(of: block))))
    }

    /// How far below `top` the held heading reaches, and with it where the file headers are held.
    static func cover(atTop top: Double, document: DiffDocument, layout: DiffLayout) -> Double {
        guard let heading = heading(atTop: top, document: document, layout: layout) else { return 0 }
        return max(heading.y + layout.metrics.groupHeight - top, 0)
    }

    /// How far above a file's header the view starts when the header shows just below its group's
    /// heading, which is where Next File and Previous File leave it.
    static func offset(ofFile file: Int, document: DiffDocument, layout: DiffLayout) -> Double {
        document.fileGroupHeadings.indices.contains(file) && document.fileGroupHeadings[file] != nil ? layout.metrics.groupHeight : 0
    }
}
