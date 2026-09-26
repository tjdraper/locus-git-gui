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

    private let canvas: DiffCanvasView
    private var groups: [Int: DiffGroupHeaderView] = [:]
    private var headers: [Int: DiffFileHeaderView] = [:]
    private var notices: [Int: DiffNoticeView] = [:]
    private var images: [Int: DiffImagesView] = [:]
    private var hunks: [Int: DiffHunkBarView] = [:]
    private var spareGroups: [DiffGroupHeaderView] = []
    private var spareHeaders: [DiffFileHeaderView] = []
    private var spareNotices: [DiffNoticeView] = []
    private var spareImages: [DiffImagesView] = []
    private var spareHunks: [DiffHunkBarView] = []

    init(canvas: DiffCanvasView) {
        self.canvas = canvas
    }

    /// Everything goes when the diff changes, since a block's index then means something else.
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
            return
        }
        let visible = canvas.visibleRect
        let layout = content.layout
        let document = content.document
        let blocks = layout.blocks(from: visible.minY, to: visible.maxY)
        var shownFiles = Set<Int>()
        var shownGroups = Set<Int>()
        var shownNotices = Set<Int>()
        var shownImages = Set<Int>()
        var shownHunks = Set<Int>()
        for block in blocks {
            let frame = layout.frame(of: block)
            let rect = NSRect(x: 0, y: frame.minY, width: canvas.bounds.width, height: frame.maxY - frame.minY)
            switch document.blocks[block] {
            case let .group(file):
                shownGroups.insert(block)
                configureGroup?(place(block, in: &groups, spares: &spareGroups, at: rect), file)
            case let .hunk(file, hunk):
                guard let configureHunk else { break }
                shownHunks.insert(block)
                configureHunk(place(block, in: &hunks, spares: &spareHunks, at: rect), file, hunk)
            case let .notice(file, notice):
                shownNotices.insert(block)
                configureNotice?(place(block, in: &notices, spares: &spareNotices, at: rect), file, notice)
            case let .images(file):
                shownImages.insert(file)
                configureImages?(place(file, in: &images, spares: &spareImages, at: rect), file)
            default:
                break
            }
            shownFiles.insert(document.blocks[block].file)
        }
        for file in shownFiles {
            let headerTop = layout.top(of: document.fileStarts[file])
            let fileEnd = layout.top(of: document.fileEnds[file])
            let height = layout.metrics.headerHeight
            let y = min(max(visible.minY, headerTop), fileEnd - height)
            let view = headers[file] ?? add(from: &spareHeaders, below: false)
            headers[file] = view
            view.frame = NSRect(x: 0, y: y, width: canvas.bounds.width, height: height)
            configureHeader?(view, file)
        }
        retire(&groups, keeping: shownGroups, into: &spareGroups)
        retire(&hunks, keeping: shownHunks, into: &spareHunks)
        retire(&headers, keeping: shownFiles, into: &spareHeaders)
        retire(&notices, keeping: shownNotices, into: &spareNotices)
        retire(&images, keeping: shownImages, into: &spareImages)
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
