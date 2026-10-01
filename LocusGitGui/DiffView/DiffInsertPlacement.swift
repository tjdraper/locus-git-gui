import AppKit

/// Where the inserts whoever shows the diff puts into it go, and which lines picked in the diff
/// they can be put below.
extension DiffViewController {
    /// The rows with the inserts among them, each as tall as whoever shows the diff measures it.
    func laidOut(collapsed: Set<Int>, style: DiffDocument.Style, metrics: DiffLayout.Metrics, width: Double) -> (DiffDocument, DiffLayout) {
        let document = DiffDocument(files: files, collapsed: collapsed, style: style, headsGroups: describeGroup != nil, inserts: inserts)
        let heights = Dictionary(inserts.map { ($0.id, insertHeight?($0.id, width) ?? 0) }) { first, _ in first }
        let layout = DiffLayout(
            document: document,
            files: files,
            metrics: metrics,
            width: width,
            numberColumns: numberColumns,
            insertHeights: heights
        )
        return (document, layout)
    }

    /// For a right-click, with what can be done to the lines clicked first.
    func canvasMenu(forFile file: Int?) -> NSMenu? {
        guard let file else { return nil }
        let copies = canvas.selection.map { !$0.isEmpty } ?? false
        var menu = menu(forFile: file)
        if let lineActions, let target = menuLineTarget() {
            menu.lineActions = lineActions(target)
        }
        return menu.make(copying: copies ? canvas : nil)
    }

    var insertView: ((_ id: String) -> NSView?)? {
        get { blockViews.insertView }
        set { blockViews.insertView = newValue }
    }

    /// The lines selected, for a command from the menu bar.
    var selectedLineTarget: DiffLineTarget? {
        guard let content = canvas.content, let selection = canvas.selection, !selection.isEmpty else { return nil }
        let end = selection.end.offset == 0 && selection.end.block > selection.start.block ? selection.end.block - 1 : selection.end.block
        return DiffLineTarget(blocks: selection.start.block ... end, side: selection.side, document: content.document, files: files)
    }

    /// The selected lines when the right-click is on them, and otherwise the line right-clicked.
    private func menuLineTarget() -> DiffLineTarget? {
        guard let content = canvas.content, let row = canvas.menuRow else { return nil }
        if let selected = selectedLineTarget, let selection = canvas.selection,
           (selection.start.block ... selection.end.block).contains(row.block) {
            return selected
        }
        return DiffLineTarget(blocks: row.block ... row.block, side: row.side, document: content.document, files: files)
    }
}
