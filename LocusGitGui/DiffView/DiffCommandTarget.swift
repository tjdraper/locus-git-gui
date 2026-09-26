import Foundation

/// Which file a diff's file commands act on, from what's selected and what's in view.
nonisolated struct DiffCommandTarget: Sendable {
    let document: DiffDocument
    let layout: DiffLayout
    let selection: DiffSelection?
    /// The part of the diff in view, below the header stuck at the top.
    let visibleTop: Double
    let visibleBottom: Double

    /// The file with the selection in it while that's in view, and otherwise the one at the top.
    var file: Int? {
        if let selection, document.blocks.indices.contains(selection.head.block) {
            let frame = layout.frame(of: selection.head.block)
            if frame.maxY > visibleTop, frame.minY < visibleBottom {
                return document.file(at: selection.head.block)
            }
        }
        return layout.block(atY: visibleTop).flatMap(document.file(at:)) ?? document.blocks.last?.file
    }
}
