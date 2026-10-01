import AppKit

/// The views laid over the diff where drawing isn't enough: group headings and file headers with
/// their buttons, notices that offer to show left-out changes, images, and the buttons on each
/// hunk's band. Only the ones on screen exist, placed as the diff scrolls. A file's header stays at
/// the top while any of the file is in view, until the next file's header pushes it up.
final class DiffBlockViews {
    var configureGroup: ((DiffGroupHeaderView, _ file: Int) -> Void)?
    var configureHeader: ((DiffFileHeaderView, _ file: Int) -> Void)?
    var configureNotice: ((DiffNoticeView, _ file: Int, DiffDocument.Notice) -> Void)?
    var configureImages: ((DiffImagesView, _ file: Int) -> Void)?
    /// Nil for a diff whose hunks have nothing to do, which then has no views over its hunks.
    var configureHunk: ((DiffHunkBarView, _ file: Int, _ hunk: Int) -> Void)?
    /// Whoever shows the diff keeps an insert's view, so what's typed into one survives it
    /// scrolling out of sight, and asked for it each time, since they may replace it.
    var insertView: ((_ id: String) -> NSView?)?

    private let canvas: DiffCanvasView
    private var groups: [Int: DiffGroupHeaderView] = [:]
    private var headers: [Int: DiffFileHeaderView] = [:]
    private var notices: [Int: DiffNoticeView] = [:]
    private var images: [Int: DiffImagesView] = [:]
    private var hunks: [Int: DiffHunkBarView] = [:]
    private var inserts: [String: NSView] = [:]
    private var spareGroups: [DiffGroupHeaderView] = []
    private var spareHeaders: [DiffFileHeaderView] = []
    private var spareNotices: [DiffNoticeView] = []
    private var spareImages: [DiffImagesView] = []
    private var spareHunks: [DiffHunkBarView] = []

    init(canvas: DiffCanvasView) {
        self.canvas = canvas
    }

    /// Everything goes when the diff changes, since a block's index then means something else.
    /// Inserts are known by their own ids, and stay until `update` finds them gone, so one being
    /// typed into keeps focus while the diff is read again.
    func removeAll() {
        for view in groups.values {
            view.removeFromSuperview()
            spareGroups.append(view)
        }
        for view in hunks.values {
            view.removeFromSuperview()
            spareHunks.append(view)
        }
        for view in headers.values {
            view.removeFromSuperview()
            spareHeaders.append(view)
        }
        for view in notices.values {
            view.removeFromSuperview()
            spareNotices.append(view)
        }
        for view in images.values {
            view.removeFromSuperview()
            spareImages.append(view)
        }
        groups = [:]
        headers = [:]
        notices = [:]
        images = [:]
        hunks = [:]
    }

    func update() {
        guard let content = canvas.content else {
            removeAll()
            for view in inserts.values {
                view.removeFromSuperview()
            }
            inserts = [:]
            return
        }
        let visible = canvas.visibleRect
        let layout = content.layout
        let document = content.document
        var shown = Shown()
        for block in layout.blocks(from: visible.minY, to: visible.maxY) {
            let frame = layout.frame(of: block)
            let rect = NSRect(x: 0, y: frame.minY, width: canvas.bounds.width, height: frame.maxY - frame.minY)
            show(document.blocks[block], at: block, in: rect, shown: &shown)
        }
        let heading = DiffStickyHeadings.heading(atTop: visible.minY, document: document, layout: layout)
        if let heading {
            shown.groups.insert(heading.block)
            holdAtTop(heading, width: canvas.bounds.width, height: layout.metrics.groupHeight, file: document.blocks[heading.block].file)
        }
        placeHeaders(of: shown.files, in: content, below: heading)
        retire(&groups, keeping: shown.groups, into: &spareGroups)
        retire(&hunks, keeping: shown.hunks, into: &spareHunks)
        retire(&headers, keeping: shown.files, into: &spareHeaders)
        retire(&notices, keeping: shown.notices, into: &spareNotices)
        retire(&images, keeping: shown.images, into: &spareImages)
        for (id, view) in inserts where !shown.inserts.contains(id) {
            view.removeFromSuperview()
            inserts[id] = nil
        }
    }

    /// What `update` has placed, so the rest can be put away.
    private struct Shown {
        var files = Set<Int>()
        var groups = Set<Int>()
        var notices = Set<Int>()
        var images = Set<Int>()
        var hunks = Set<Int>()
        var inserts = Set<String>()
    }

    private func show(_ block: DiffDocument.Block, at index: Int, in rect: NSRect, shown: inout Shown) {
        switch block {
        case let .group(file):
            shown.groups.insert(index)
            configureGroup?(place(index, in: &groups, spares: &spareGroups, at: rect), file)
        case let .hunk(file, hunk):
            guard let configureHunk else { break }
            shown.hunks.insert(index)
            configureHunk(place(index, in: &hunks, spares: &spareHunks, at: rect), file, hunk)
        case let .notice(file, notice):
            shown.notices.insert(index)
            configureNotice?(place(index, in: &notices, spares: &spareNotices, at: rect), file, notice)
        case let .images(file):
            shown.images.insert(file)
            configureImages?(place(file, in: &images, spares: &spareImages, at: rect), file)
        case let .insert(_, id):
            guard let view = insertView?(id) else { break }
            shown.inserts.insert(id)
            if let replaced = inserts[id], replaced !== view {
                replaced.removeFromSuperview()
            }
            if view.superview !== canvas {
                canvas.addSubview(view, positioned: .below, relativeTo: nil)
            }
            inserts[id] = view
            view.frame = rect
        default:
            break
        }
        shown.files.insert(block.file)
    }

    /// Each at the top of its file, or held at the top of the view, below the held group heading
    /// when the file is in its group, until the file's end pushes it up.
    private func placeHeaders(of files: Set<Int>, in content: DiffCanvasView.Content, below heading: DiffStickyHeadings.Heading?) {
        let (document, layout, top) = (content.document, content.layout, canvas.visibleRect.minY)
        let cover = DiffStickyHeadings.cover(atTop: top, document: document, layout: layout)
        for file in files {
            let headerTop = layout.top(of: document.fileStarts[file])
            let fileEnd = layout.top(of: document.fileEnds[file])
            let height = layout.metrics.headerHeight
            let held = heading != nil && document.fileGroupHeadings[file] == heading?.block ? top + cover : top
            let view = headers[file] ?? add(from: &spareHeaders, below: false)
            headers[file] = view
            view.frame = NSRect(x: 0, y: min(max(held, headerTop), fileEnd - height), width: canvas.bounds.width, height: height)
            configureHeader?(view, file)
        }
    }

    /// Over the rows, the hunk bars and the file headers, which slide under it as they scroll up.
    private func holdAtTop(_ heading: DiffStickyHeadings.Heading, width: CGFloat, height: Double, file: Int) {
        let view = groups[heading.block] ?? add(from: &spareGroups, below: false)
        groups[heading.block] = view
        view.frame = NSRect(x: 0, y: heading.y, width: width, height: height)
        if canvas.subviews.last !== view {
            canvas.addSubview(view, positioned: .above, relativeTo: nil)
        }
        configureGroup?(view, file)
    }

    /// Everything but the file headers, which go over them.
    private func place<View: NSView>(_ key: Int, in views: inout [Int: View], spares: inout [View], at rect: NSRect) -> View {
        let view = views[key] ?? add(from: &spares, below: true)
        views[key] = view
        view.frame = rect
        return view
    }

    /// Group headings, notices, images and hunk bars go under the headers, which slide over them
    /// while stuck at the top.
    private func add<View: NSView>(from spares: inout [View], below: Bool) -> View {
        let view = spares.popLast() ?? View(frame: .zero)
        canvas.addSubview(view, positioned: below ? .below : .above, relativeTo: nil)
        return view
    }

    private func retire<View: NSView>(_ views: inout [Int: View], keeping kept: Set<Int>, into spares: inout [View]) {
        for (key, view) in views where !kept.contains(key) {
            view.removeFromSuperview()
            spares.append(view)
            views[key] = nil
        }
    }
}
